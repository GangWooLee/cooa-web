require "test_helper"

# A dedicated NON-superuser, NO-BYPASSRLS connection for the app-path smoke (distinct from
# rls_isolation_test's RlsAppConnection so both can run in one process).
class CooaAppSmokeConnection < ActiveRecord::Base
  self.abstract_class = true
end

# Phase 2a-2 e2e SMOKE: proves the REAL app query paths WORK end-to-end under the cooa_app role
# (NO BYPASSRLS) + a tenant context, and ISOLATE cross-tenant. Complements rls_isolation_test
# (foundation) by exercising the login lookup, dashboard scope, and a same-tenant INSERT — the latter
# is the regression guard for the sequence-USAGE grant (bigserial PKs fail INSERT without it).
class RlsAppConnectionTest < ActiveSupport::TestCase
  self.use_transactional_tests = false # cross-connection visibility needs committed rows

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
    owner.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cooa_app") # bigserial INSERT
    owner.execute("GRANT SELECT, INSERT ON audit_logs TO cooa_app")                    # append-only (no UPDATE/DELETE)

    @org_a = Organization.create!(name: "App Tenant A", region: "JP")
    @org_b = Organization.create!(name: "App Tenant B", region: "US")
    @user_a = User.create!(name: "사용자A", role: "ra", avatar_color: "#111111", email: "ua@a.test")
    @acct_a = Account.create!(tenant_id: @org_a.id, user_id: @user_a.id, email: "a@a.test", status: "active")
    @acct_b = Account.create!(tenant_id: @org_b.id, email: "b@b.test", status: "active")

    cfg = ActiveRecord::Base.connection_db_config.configuration_hash.merge(username: "cooa_app", password: "cooa_dev_pw")
    CooaAppSmokeConnection.establish_connection(cfg)
    @app = CooaAppSmokeConnection.connection
  end

  teardown do
    CooaAppSmokeConnection.remove_connection
    ids = [ @org_a&.id, @org_b&.id ].compact
    Product.where(tenant_id: ids).delete_all
    Account.where(tenant_id: ids).delete_all # accounts.user_id → users: before destroying the user
    @user_a&.destroy
    [ @org_a, @org_b ].each { |o| o&.destroy }
  end

  # Login lookup (SessionsController#new/#create): accounts ⋈ users, tenant-scoped, under cooa_app.
  test "login account lookup is tenant-scoped and joins the linked user" do
    rows = TenantContext.with_tenant(@org_a.id, connection: @app) do
      @app.exec_query("SELECT a.email, u.name FROM accounts a LEFT JOIN users u ON u.id = a.user_id " \
                      "WHERE a.status = 'active'").to_a
    end
    assert_equal [ { "email" => "a@a.test", "name" => "사용자A" } ], rows
  end

  test "another tenant's account_id is invisible (cannot be honored at login)" do
    found = TenantContext.with_tenant(@org_a.id, connection: @app) do
      @app.select_value("SELECT COUNT(*) FROM accounts WHERE id = '#{@acct_b.id}'").to_i
    end
    assert_equal 0, found
  end

  test "dashboard products are tenant-scoped" do
    Product.create!(tenant_id: @org_a.id, name: "A-root", kind: "folder")
    Product.create!(tenant_id: @org_b.id, name: "B-root", kind: "folder")
    names = TenantContext.with_tenant(@org_a.id, connection: @app) do
      @app.select_values("SELECT name FROM products WHERE parent_id IS NULL")
    end
    assert_equal [ "A-root" ], names
  end

  # The isolation FLOOR (P5 benchmark): with NO tenant context the policy casts the unset GUC to NULL and
  # matches no row — a SELECT returns 0 (fail-CLOSED), never all rows. A regression here = a cross-tenant leak.
  test "no tenant context → SELECT is fail-CLOSED (0 rows, not all)" do
    Product.create!(tenant_id: @org_a.id, name: "floor", kind: "folder") # committed via owner
    n = @app.select_value("SELECT COUNT(*) FROM products").to_i          # cooa_app, NO with_tenant
    assert_equal 0, n, "an unset tenant GUC must expose 0 rows, not leak the table"
  end

  # Sequence-grant regression: a same-tenant INSERT (bigserial PK → needs sequence USAGE) must SUCCEED.
  # Covers ALL domain bigserial INSERTs (products, screening_runs, …) — one GRANT ON ALL SEQUENCES.
  test "same-tenant domain INSERT succeeds (sequence USAGE granted)" do
    n = TenantContext.with_tenant(@org_a.id, connection: @app) do
      @app.execute("INSERT INTO products (tenant_id, name, kind, position, created_at, updated_at) " \
                   "VALUES ('#{@org_a.id}', 'made-by-cooa_app', 'folder', 0, now(), now())")
      @app.select_value("SELECT COUNT(*) FROM products").to_i
    end
    assert_equal 1, n
  end

  test "cross-tenant INSERT is blocked by WITH CHECK" do
    assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.with_tenant(@org_a.id, connection: @app) do
        @app.execute("INSERT INTO products (tenant_id, name, kind, position, created_at, updated_at) " \
                     "VALUES ('#{@org_b.id}', 'evil', 'folder', 0, now(), now())")
      end
    end
  end

  # Audit append-only under cooa_app (P2 M-1 + m-1): INSERT REQUIRES the tenant GUC — so the deny-audit
  # path must re-establish it (rescue_from runs after the request tx unwinds, GUC cleared); UPDATE/DELETE
  # are denied (SELECT/INSERT-only grant + immutable trigger). test=owner suites mask this (BYPASSRLS).
  test "audit_logs needs tenant context to INSERT and is immutable under cooa_app" do
    cols = "(tenant_id, action, resource_type, outcome, tenant_seq, chain_hash)"
    vals = "('#{@org_a.id}', 'probe', 'X', 'deny', 1, 'h')"
    # (a) no GUC → RLS WITH CHECK blocks (the M-1 failure mode the rescue must avoid)
    assert_raises(ActiveRecord::StatementInvalid) { @app.execute("INSERT INTO audit_logs #{cols} VALUES #{vals}") }
    # (b) with the tenant context → succeeds
    id = TenantContext.with_tenant(@org_a.id, connection: @app) do
      @app.execute("INSERT INTO audit_logs #{cols} VALUES #{vals}")
      @app.select_value("SELECT id FROM audit_logs WHERE action = 'probe'")
    end
    assert id, "deny audit row persists when the tenant context is set"
    # (c) UPDATE / DELETE denied (append-only)
    assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.with_tenant(@org_a.id, connection: @app) { @app.execute("UPDATE audit_logs SET action='x' WHERE id=#{id}") }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.with_tenant(@org_a.id, connection: @app) { @app.execute("DELETE FROM audit_logs WHERE id=#{id}") }
    end
  ensure
    ActiveRecord::Base.connection.execute("TRUNCATE audit_logs")
  end
end
