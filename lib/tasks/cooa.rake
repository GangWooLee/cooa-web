# RLS posture guards (ADR-002 §7.1). Run in CI to fail the build if a tenant-scoped table
# is missing ENABLE+FORCE RLS + a policy, or if the app role can bypass RLS.
namespace :rls do
  # Tables that must NOT carry tenant RLS:
  #   - infra (Rails/ActiveStorage internals)
  #   - global regulatory KB (shared read-only across tenants — intentionally not tenant-scoped)
  #   - TEMP: legacy demo domain tables (RLS added in Phase 0b, then removed from this list)
  PERMANENT_EXEMPT = %w[
    schema_migrations ar_internal_metadata
    active_storage_attachments active_storage_blobs active_storage_variant_records
    ingredient_limits label_requirements ad_risk_expressions
    users
  ].freeze
  # Phase 0b complete — all domain tables now carry RLS; nothing left to exempt temporarily.
  TEMP_EXEMPT_UNTIL_PHASE_0B = %w[].freeze

  desc "Fail if any tenant-scoped table lacks ENABLE+FORCE RLS + a policy"
  task audit: :environment do
    exempt = (PERMANENT_EXEMPT + TEMP_EXEMPT_UNTIL_PHASE_0B).uniq
    list = exempt.map { |t| ActiveRecord::Base.connection.quote(t) }.join(",")
    sql = <<~SQL
      SELECT c.relname,
             c.relrowsecurity      AS enabled,
             c.relforcerowsecurity AS forced,
             EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname) AS has_policy
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
        AND c.relname NOT IN (#{list})
      ORDER BY c.relname
    SQL
    rows = ActiveRecord::Base.connection.exec_query(sql).to_a
    bool = ->(v) { ActiveModel::Type::Boolean.new.cast(v) }
    bad = rows.reject { |r| bool.call(r["enabled"]) && bool.call(r["forced"]) && bool.call(r["has_policy"]) }
    if bad.any?
      abort "RLS audit FAILED — tenant tables missing ENABLE+FORCE+policy: #{bad.map { |r| r['relname'] }.join(', ')}"
    end
    puts "RLS audit OK — #{rows.size} tenant-scoped table(s) ENABLE+FORCE+policy (exempt: #{exempt.size})."

    # Append-only guard: such tables must have NO cooa_app UPDATE/DELETE + an immutability trigger.
    conn = ActiveRecord::Base.connection
    APPEND_ONLY_TABLES.each do |t|
      privs = conn.select_values(<<~SQL)
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE grantee = 'cooa_app' AND table_schema = 'public' AND table_name = '#{t}'
      SQL
      leaked = privs & %w[UPDATE DELETE]
      abort "append-only #{t}: cooa_app has #{leaked.join(',')} (must be SELECT/INSERT only)" if leaked.any?
      trig = conn.select_value("SELECT 1 FROM pg_trigger WHERE tgrelid = '#{t}'::regclass AND NOT tgisinternal LIMIT 1")
      abort "append-only #{t}: missing immutability trigger" if trig.nil?
    end
    puts "Append-only OK — #{APPEND_ONLY_TABLES.size} table(s): no cooa_app UPDATE/DELETE + trigger."
  end

  # Tenant-scoped tables (RLS) get DML; global KB + users get read-only; ActiveStorage gets DML
  # (upload=INSERT, analyze=UPDATE, purge=DELETE, variant/preview=INSERT — 실사용에서 SELECT만으론
  # 업로드가 PG::InsufficientPrivilege 500. 테넌트 격리는 record 측 RLS가 담당, blob은 인프라).
  RLS_TABLES = %w[
    organizations accounts role_assignments
    workspaces products components component_versions annotations annotation_comments
    ingredients label_texts screening_runs screening_findings product_members product_properties
    approval_requests approval_steps approval_request_reviewers
    invitations
  ].freeze
  READ_ONLY_TABLES = %w[
    ingredient_limits label_requirements ad_risk_expressions users
    schema_migrations ar_internal_metadata
  ].freeze
  ATTACHMENT_TABLES = %w[
    active_storage_blobs active_storage_attachments active_storage_variant_records
  ].freeze
  # Append-only (ADR-002 §5.4): cooa_app gets SELECT+INSERT only — no UPDATE/DELETE (a trigger enforces
  # immutability even for the owner). RLS still applies (these ARE tenant-scoped).
  APPEND_ONLY_TABLES = %w[audit_logs].freeze

  desc "Grant the non-owner app role (cooa_app) privileges (structure.sql strips GRANTs — re-apply after schema load)"
  task grant_app: :environment do
    conn = ActiveRecord::Base.connection
    db = conn.current_database
    conn.execute(%(GRANT CONNECT ON DATABASE "#{db}" TO cooa_app))
    conn.execute("GRANT USAGE ON SCHEMA public TO cooa_app")
    conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{RLS_TABLES.join(', ')} TO cooa_app")
    conn.execute("GRANT SELECT ON #{READ_ONLY_TABLES.join(', ')} TO cooa_app")
    conn.execute("GRANT SELECT, INSERT ON #{APPEND_ONLY_TABLES.join(', ')} TO cooa_app") # append-only: no update/delete
    # ActiveStorage 런타임 경로: attach=INSERT / analyze=UPDATE(metadata) / purge=DELETE / preview·variant=INSERT.
    # [리스크 등재] AS 3종은 tenant 컬럼·RLS가 없어(blob=인프라) 이 DML로 DB 백스톱 없이 앱 계층
    # (RLS 스코프 record 경유 purge·signed_id)만이 격리를 담당한다. SQLi 시 폭발반경이 read→destroy로
    # 커지는 트레이드오프 — 장기적으론 blobs/attachments tenant_id 스코핑 검토(보안 트랙).
    conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{ATTACHMENT_TABLES.join(', ')} TO cooa_app")
    # Domain bigserial PKs need sequence USAGE for INSERT (else "permission denied for sequence").
    conn.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cooa_app")
    conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO cooa_app")
    puts "Granted cooa_app on #{db} (#{RLS_TABLES.size} RLS + #{READ_ONLY_TABLES.size} read-only + #{ATTACHMENT_TABLES.size} attachment DML + #{APPEND_ONLY_TABLES.size} append-only + sequences)."
  end

  # 부족부여(under-grant) 감사 — rls:audit의 사각지대를 메움(R8 · docs/dev-discipline.md).
  # rls:audit는 "RLS 누락·과다부여"만 검사해서, active_storage_blobs INSERT 누락 같은 부족부여는
  # 그린으로 통과했다(실사용 업로드 500의 원인). 이 태스크는 (1) 모든 public 테이블이 grant 그룹에
  # 분류되어 있는지(신규 테이블이 조용히 무권한으로 남는 것 차단), (2) 그룹별 기대 verb를 cooa_app이
  # 실제로 갖는지 has_table_privilege로 검증한다. 스키마 로드/마이그 후 grant_app과 함께 실행.
  desc "Fail if cooa_app lacks expected privileges (under-grant) or a table is unclassified"
  task grant_audit: :environment do
    conn = ActiveRecord::Base.connection
    expected = {}
    RLS_TABLES.each        { |t| expected[t] = %w[SELECT INSERT UPDATE DELETE] }
    ATTACHMENT_TABLES.each { |t| expected[t] = %w[SELECT INSERT UPDATE DELETE] }
    READ_ONLY_TABLES.each  { |t| expected[t] = %w[SELECT] }
    APPEND_ONLY_TABLES.each { |t| expected[t] = %w[SELECT INSERT] }

    all_tables = conn.select_values(<<~SQL)
      SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname
    SQL
    unclassified = all_tables - expected.keys
    if unclassified.any?
      abort "grant audit FAILED — 미분류 테이블(cooa.rake의 grant 그룹에 추가 필요): #{unclassified.join(', ')}"
    end

    missing = []
    expected.each do |table, verbs|
      next unless all_tables.include?(table)
      verbs.each do |verb|
        ok = conn.select_value("SELECT has_table_privilege('cooa_app', #{conn.quote(table)}, #{conn.quote(verb)})")
        missing << "#{table}:#{verb}" unless ActiveModel::Type::Boolean.new.cast(ok)
      end
    end
    # 읽기전용 테이블의 과다부여(역방향)도 여기서 잡는다 — KB 무결성.
    leaked = []
    READ_ONLY_TABLES.each do |table|
      next unless all_tables.include?(table)
      %w[INSERT UPDATE DELETE].each do |verb|
        bad = conn.select_value("SELECT has_table_privilege('cooa_app', #{conn.quote(table)}, #{conn.quote(verb)})")
        leaked << "#{table}:#{verb}" if ActiveModel::Type::Boolean.new.cast(bad)
      end
    end
    # 시퀀스 대표 검사(ALL SEQUENCES + 기본권한이 유지되는지)
    seq = conn.select_value("SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='S' LIMIT 1")
    if seq
      ok = conn.select_value("SELECT has_sequence_privilege('cooa_app', #{conn.quote(seq)}, 'USAGE')")
      missing << "sequence #{seq}:USAGE" unless ActiveModel::Type::Boolean.new.cast(ok)
    end

    abort "grant audit FAILED — 부족부여: #{missing.join(', ')}" if missing.any?
    abort "grant audit FAILED — 읽기전용 테이블 과다부여: #{leaked.join(', ')}" if leaked.any?
    puts "Grant audit OK — #{expected.size} table(s) classified · under-grant 0 · read-only leak 0. (solid_* 별도 DB는 prod 컷오버 체크리스트로 — docs/prod-cutover.md §7)"
  end
end
