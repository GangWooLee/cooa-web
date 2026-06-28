require "test_helper"

# A dedicated NON-superuser, NO-BYPASSRLS connection. RLS is only meaningfully verified through a
# role that cannot bypass it — a superuser (the default dev/test connection) makes every assertion vacuous.
class RlsAppConnection < ActiveRecord::Base
  self.abstract_class = true
end

# Verifies the Phase 0 isolation foundation (ADR-002 §7): tenant-scoped reads, fail-CLOSED on unset
# context, WITH CHECK on writes, and that the app role genuinely cannot bypass RLS.
class RlsIsolationTest < ActiveSupport::TestCase
  # Cross-connection visibility needs committed rows → opt out of transactional fixtures.
  self.use_transactional_tests = false

  setup do
    owner = ActiveRecord::Base.connection
    db = owner.current_database
    # structure.sql strips GRANTs (pg_dump -x); (re)apply them so cooa_app can connect + DML.
    owner.execute(%(GRANT CONNECT ON DATABASE "#{db}" TO cooa_app))
    owner.execute("GRANT USAGE ON SCHEMA public TO cooa_app")
    owner.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON organizations, accounts, role_assignments TO cooa_app")

    # Seed two tenants as the owner (superuser bypasses RLS for setup).
    @org_a = Organization.create!(name: "Tenant A", region: "JP")
    @org_b = Organization.create!(name: "Tenant B", region: "US")
    @acct_a = Account.create!(tenant_id: @org_a.id, email: "a@example.com", status: "active", display_name: "A")
    @acct_b = Account.create!(tenant_id: @org_b.id, email: "b@example.com", status: "active", display_name: "B")

    cfg = ActiveRecord::Base.connection_db_config.configuration_hash.merge(
      username: "cooa_app", password: "cooa_dev_pw"
    )
    RlsAppConnection.establish_connection(cfg)
    @app = RlsAppConnection.connection
  end

  teardown do
    RlsAppConnection.remove_connection
    ids = [@org_a&.id, @org_b&.id].compact
    RoleAssignment.where(tenant_id: ids).delete_all
    Account.where(tenant_id: ids).delete_all
    [@org_a, @org_b].each { |o| o&.destroy }
  end

  test "app role is non-superuser and cannot bypass RLS" do
    r = @app.exec_query("SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user").first
    refute ActiveModel::Type::Boolean.new.cast(r["rolsuper"]), "app role must not be a superuser"
    refute ActiveModel::Type::Boolean.new.cast(r["rolbypassrls"]), "app role must not have BYPASSRLS"
  end

  test "SELECT is scoped to the active tenant" do
    a = TenantContext.with_tenant(@org_a.id, connection: @app) { @app.select_values("SELECT email FROM accounts") }
    assert_equal ["a@example.com"], a, "tenant A must see only its own account"

    b = TenantContext.with_tenant(@org_b.id, connection: @app) { @app.select_values("SELECT email FROM accounts") }
    assert_equal ["b@example.com"], b, "tenant B must see only its own account"
  end

  test "unset tenant context yields zero rows (fail-CLOSED, not whole table)" do
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM accounts").to_i
  end

  test "WITH CHECK blocks inserting a row into another tenant" do
    assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.with_tenant(@org_a.id, connection: @app) do
        @app.execute(<<~SQL)
          INSERT INTO accounts (id, tenant_id, email, status, token_version, is_cooa_staff, created_at, updated_at)
          VALUES (gen_random_uuid(), '#{@org_b.id}', 'evil@example.com', 'active', 0, false, now(), now())
        SQL
      end
    end
  end
end
