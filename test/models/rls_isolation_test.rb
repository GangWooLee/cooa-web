require "test_helper"

# A dedicated NON-superuser, NO-BYPASSRLS connection. RLS is only meaningfully verified through a
# role that cannot bypass it — a superuser (the default dev/test connection) makes assertions vacuous.
class RlsAppConnection < ActiveRecord::Base
  self.abstract_class = true
end

# Verifies the Phase 0a/0b isolation foundation (ADR-002 §7) across foundation + domain tables:
# tenant-scoped reads, fail-CLOSED on unset context, WITH CHECK on writes, no-bypass app role.
class RlsIsolationTest < ActiveSupport::TestCase
  # Cross-connection visibility needs committed rows → opt out of transactional fixtures.
  self.use_transactional_tests = false

  # cooa_app DML targets (RLS) + read-only (global KB / users / active_storage). structure.sql strips
  # GRANTs (pg_dump -x), so (re)apply them here as the owner — keeps the test self-sufficient.
  RLS_TABLES = "organizations, accounts, role_assignments, products, components, component_versions, " \
               "annotations, annotation_comments, ingredients, label_texts, screening_runs, " \
               "screening_findings, product_members, product_properties".freeze
  READ_ONLY = "users, ingredient_limits, label_requirements, ad_risk_expressions".freeze

  setup do
    owner = ActiveRecord::Base.connection
    db = owner.current_database
    owner.execute(%(GRANT CONNECT ON DATABASE "#{db}" TO cooa_app))
    owner.execute("GRANT USAGE ON SCHEMA public TO cooa_app")
    owner.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{RLS_TABLES} TO cooa_app")
    owner.execute("GRANT SELECT ON #{READ_ONLY} TO cooa_app")

    # Two tenants seeded as the owner (superuser bypasses RLS for setup).
    @org_a = Organization.create!(name: "RLS Tenant A", region: "JP")
    @org_b = Organization.create!(name: "RLS Tenant B", region: "US")
    @acct_a = Account.create!(tenant_id: @org_a.id, email: "a@example.com", status: "active", display_name: "A")
    @acct_b = Account.create!(tenant_id: @org_b.id, email: "b@example.com", status: "active", display_name: "B")

    cfg = ActiveRecord::Base.connection_db_config.configuration_hash.merge(username: "cooa_app", password: "cooa_dev_pw")
    RlsAppConnection.establish_connection(cfg)
    @app = RlsAppConnection.connection
  end

  teardown do
    RlsAppConnection.remove_connection
    ids = [@org_a&.id, @org_b&.id].compact
    Product.where(tenant_id: ids).delete_all
    RoleAssignment.where(tenant_id: ids).delete_all
    Account.where(tenant_id: ids).delete_all
    [@org_a, @org_b].each { |o| o&.destroy }
  end

  # ── role guarantee ───────────────────────────────────────────────────────
  test "app role is non-superuser and cannot bypass RLS" do
    r = @app.exec_query("SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user").first
    refute ActiveModel::Type::Boolean.new.cast(r["rolsuper"]), "app role must not be a superuser"
    refute ActiveModel::Type::Boolean.new.cast(r["rolbypassrls"]), "app role must not have BYPASSRLS"
  end

  # ── foundation: accounts ─────────────────────────────────────────────────
  test "accounts SELECT is scoped to the active tenant" do
    a = TenantContext.with_tenant(@org_a.id, connection: @app) { @app.select_values("SELECT email FROM accounts") }
    assert_equal ["a@example.com"], a
    b = TenantContext.with_tenant(@org_b.id, connection: @app) { @app.select_values("SELECT email FROM accounts") }
    assert_equal ["b@example.com"], b
  end

  test "accounts: unset tenant context yields zero rows (fail-CLOSED)" do
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM accounts").to_i
  end

  test "accounts: WITH CHECK blocks inserting into another tenant" do
    assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.with_tenant(@org_a.id, connection: @app) do
        @app.execute(<<~SQL)
          INSERT INTO accounts (id, tenant_id, email, status, token_version, is_cooa_staff, created_at, updated_at)
          VALUES (gen_random_uuid(), '#{@org_b.id}', 'evil@example.com', 'active', 0, false, now(), now())
        SQL
      end
    end
  end

  # ── domain: products (self-ref tree, composite FK) ───────────────────────
  test "domain products SELECT is scoped to the active tenant" do
    Product.create!(tenant_id: @org_a.id, name: "P-A", kind: "folder")
    Product.create!(tenant_id: @org_b.id, name: "P-B", kind: "folder")
    a = TenantContext.with_tenant(@org_a.id, connection: @app) { @app.select_values("SELECT name FROM products") }
    assert_equal ["P-A"], a
    b = TenantContext.with_tenant(@org_b.id, connection: @app) { @app.select_values("SELECT name FROM products") }
    assert_equal ["P-B"], b
  end

  test "domain products: unset context yields zero rows (fail-CLOSED)" do
    Product.create!(tenant_id: @org_a.id, name: "P-A", kind: "folder")
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM products").to_i
  end

  test "domain products: WITH CHECK blocks inserting into another tenant" do
    assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.with_tenant(@org_a.id, connection: @app) do
        @app.execute(<<~SQL)
          INSERT INTO products (tenant_id, name, kind, position, created_at, updated_at)
          VALUES ('#{@org_b.id}', 'X', 'folder', 0, now(), now())
        SQL
      end
    end
  end
end
