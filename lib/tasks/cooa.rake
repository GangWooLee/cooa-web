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
  end

  # 14 tenant-scoped tables (RLS) get DML; global KB + users + active_storage get read-only.
  RLS_TABLES = %w[
    organizations accounts role_assignments
    products components component_versions annotations annotation_comments
    ingredients label_texts screening_runs screening_findings product_members product_properties
  ].freeze
  READ_ONLY_TABLES = %w[
    ingredient_limits label_requirements ad_risk_expressions users
    active_storage_attachments active_storage_blobs active_storage_variant_records
  ].freeze

  desc "Grant the non-owner app role (cooa_app) privileges (structure.sql strips GRANTs — re-apply after schema load)"
  task grant_app: :environment do
    conn = ActiveRecord::Base.connection
    db = conn.current_database
    conn.execute(%(GRANT CONNECT ON DATABASE "#{db}" TO cooa_app))
    conn.execute("GRANT USAGE ON SCHEMA public TO cooa_app")
    conn.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{RLS_TABLES.join(', ')} TO cooa_app")
    conn.execute("GRANT SELECT ON #{READ_ONLY_TABLES.join(', ')} TO cooa_app")
    puts "Granted cooa_app on #{db} (#{RLS_TABLES.size} RLS + #{READ_ONLY_TABLES.size} read-only)."
  end
end
