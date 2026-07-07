require "test_helper"

# Regression lock — audit-log 운영 스케줄(DESIGN-운영-07 §1.1 · 02 §5.2).
# audit:verify(체인 무결)와 audit:detect_bola(BOLA 급증)는 **OWNER(BYPASSRLS) 연결로만** 전 테넌트
# 체인을 순회한다. config/recurring.yml에 직등록하면 SolidQueue 워커가 cooa_app(FORCE RLS)로
# 디스패치 → RLS가 타 테넌트를 은폐 → "이상 없음" 위양성(은폐된 무점검)이 된다. 따라서 두 태스크는
# recurring.yml에 절대 없어야 하고, owner 실행은 스크립트(bin/audit-scan·bin/release-migrate)가 담당한다.
# 아래는 YAML/파일 단언이라 test env(owner 연결) 무관하게 결정적이다.
class RecurringScheduleTest < ActiveSupport::TestCase
  RECURRING_PATH = Rails.root.join("config/recurring.yml")
  OWNER_SCRIPTS  = %w[bin/audit-scan bin/release-migrate].freeze

  test "recurring.yml production block never registers the owner-only audit tasks" do
    production = YAML.safe_load_file(RECURRING_PATH, aliases: true).fetch("production", {})
    serialized = production.to_s

    refute_match(/detect_bola/, serialized,
      "audit:detect_bola must NOT be in recurring.yml — cooa_app RLS hides other tenants (owner cron only, 07 §1.1)")
    refute_match(/audit:verify/, serialized,
      "audit:verify must NOT be in recurring.yml — chain walk needs BYPASSRLS (owner cron only, 07 §1.1)")

    # Positive guard: the file is well-formed and still carries its existing (cooa_app-safe) schedule.
    assert production.key?("clear_solid_queue_finished_jobs"),
      "recurring.yml production block should still hold clear_solid_queue_finished_jobs"
  end

  test "owner-only scan scripts exist, are executable, and carry the BYPASSRLS guard" do
    OWNER_SCRIPTS.each do |rel|
      path = Rails.root.join(rel)
      assert File.exist?(path), "#{rel} must exist (owner audit/release script)"
      assert File.executable?(path), "#{rel} must be executable (chmod +x)"

      body = File.read(path)
      # The guard queries the connected role's pg_roles attributes and aborts unless BYPASSRLS or SUPERUSER.
      assert_match(/rolbypassrls/, body, "#{rel} must contain the owner (BYPASSRLS) guard query")
      assert_match(/rolsuper/, body, "#{rel} must check rolsuper in the owner guard")
    end
  end
end
