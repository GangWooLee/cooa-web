require "test_helper"

# A dedicated NON-superuser, NO-BYPASSRLS connection (own class so it coexists with the other RLS suites in
# one process). The owner/superuser test connection makes every privilege assertion here vacuous.
class OnboardingAppConnection < ActiveRecord::Base
  self.abstract_class = true
end

# T3 (self-serve signup) DB floor. OrganizationBootstrap MINTS a brand-new tenant and creates the founding
# person + owner under the real cooa_app role — the FIRST runtime path that (a) INSERTs an `organizations`
# row (id = GUC) and (b) INSERTs a `users` row under cooa_app. Owner-based suites (BYPASSRLS + full grants)
# mask BOTH: this suite is the regression guard proving cooa_app can perform the whole bootstrap footprint
# under one new-org tenant GUC — and, critically, that `users` carries the SELECT+INSERT grant the runtime
# person-creation paths (this + InvitationAcceptance) need (SELECT-only ⇒ PG::InsufficientPrivilege at signup).
class OnboardingAppConnectionTest < ActiveSupport::TestCase
  include CommittedStateCleanup # single-sourced RLS_TABLES/READ_ONLY + leak-proof org-scoped cleanup

  self.use_transactional_tests = false # cross-connection visibility needs COMMITTED rows

  setup do
    owner = ActiveRecord::Base.connection
    db = owner.current_database
    owner.execute(%(GRANT CONNECT ON DATABASE "#{db}" TO cooa_app))
    owner.execute("GRANT USAGE ON SCHEMA public TO cooa_app")
    owner.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{RLS_TABLES} TO cooa_app")
    owner.execute("GRANT SELECT ON #{READ_ONLY} TO cooa_app")
    owner.execute("GRANT SELECT, INSERT ON users TO cooa_app")   # the T3 person-table grant under test
    owner.execute("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cooa_app") # users.id bigserial
    owner.execute("GRANT SELECT, INSERT ON audit_logs TO cooa_app")

    cfg = ActiveRecord::Base.connection_db_config.configuration_hash.merge(username: "cooa_app", password: "cooa_dev_pw")
    OnboardingAppConnection.establish_connection(cfg)
    @app = OnboardingAppConnection.connection
    @org_ids = []
    @user_emails = []
  end

  teardown do
    cleanup_committed_rls_state!(@org_ids)
    @user_emails.each { |e| isolate("user #{e}") { User.where(email: e).delete_all } }
    isolate("audit truncate") { ActiveRecord::Base.connection.execute("TRUNCATE audit_logs") }
    OnboardingAppConnection.remove_connection
  end

  # ── the WHOLE bootstrap footprint commits under cooa_app + a fresh org GUC ─────────────────────
  test "cooa_app can perform the entire org-bootstrap footprint under a newly minted tenant GUC" do
    org_id = mint_org_id
    email = track_email("founder@newco.example")

    counts = in_tenant(org_id) do
      # (1) organizations: id = GUC → WITH CHECK passes (self-serve mints its OWN tenant row)
      @app.execute(insert_org(org_id, "newco.example"))
      # (2) users: the global person row — needs the SELECT+INSERT grant + sequence USAGE (bigserial PK)
      uid = @app.select_value(<<~SQL)
        INSERT INTO users (name, email, role, avatar_color, created_at, updated_at)
        VALUES ('Founder', #{@app.quote(email)}, 'pm', '#8e0300', now(), now()) RETURNING id
      SQL
      # (3) account (+owner binding), (4) owner grant, (5) first workspace — all tenant_id = GUC
      aid = @app.select_value(<<~SQL)
        INSERT INTO accounts (tenant_id, user_id, email, status, idp_provider, idp_subject, created_at, updated_at)
        VALUES ('#{org_id}', #{uid}, #{@app.quote(email)}, 'active', 'google_oauth2', 'g-floor', now(), now()) RETURNING id
      SQL
      @app.execute(<<~SQL)
        INSERT INTO role_assignments (tenant_id, account_id, role_key, scope_type, granted_by, granted_at, created_at, updated_at)
        VALUES ('#{org_id}', '#{aid}', 'owner', 'tenant', '#{aid}', now(), now(), now())
      SQL
      @app.execute("INSERT INTO workspaces (tenant_id, name, position, created_at, updated_at) " \
                   "VALUES ('#{org_id}', 'Floor WS', 1, now(), now())")
      # (6) genesis audit row (append-only, needs the GUC to satisfy WITH CHECK)
      @app.execute("INSERT INTO audit_logs (tenant_id, action, resource_type, outcome, tenant_seq, chain_hash) " \
                   "VALUES ('#{org_id}', 'organization.bootstrap', 'Organization', 'allow', 1, 'h')")
      {
        org: @app.select_value("SELECT COUNT(*) FROM organizations WHERE id = '#{org_id}'").to_i,
        acct: @app.select_value("SELECT COUNT(*) FROM accounts WHERE tenant_id = '#{org_id}'").to_i,
        owner: @app.select_value("SELECT COUNT(*) FROM role_assignments WHERE tenant_id = '#{org_id}' AND role_key = 'owner'").to_i,
        ws: @app.select_value("SELECT COUNT(*) FROM workspaces WHERE tenant_id = '#{org_id}'").to_i
      }
    end
    assert_equal({ org: 1, acct: 1, owner: 1, ws: 1 }, counts, "the founding org + owner + workspace all committed under cooa_app")
  end

  # ── the person-table grant is the specific latent gap this guards ──────────────────────────────
  test "a users INSERT succeeds under cooa_app (person-table grant regression guard)" do
    email = track_email("solo@person.example")
    # No tenant GUC needed — users has no RLS. The ONLY thing that lets this pass is the SELECT+INSERT grant;
    # under the old SELECT-only classification this raises PG::InsufficientPrivilege (the latent signup gap).
    assert_nothing_raised do
      @app.execute("INSERT INTO users (name, email, created_at, updated_at) " \
                   "VALUES ('Solo', #{@app.quote(email)}, now(), now())")
    end
    assert_equal 1, @app.select_value("SELECT COUNT(*) FROM users WHERE email = #{@app.quote(email)}").to_i
  end

  # ── minimal grant: cooa_app may create a person but NOT mutate/remove one (over-grant guard) ────
  test "cooa_app cannot UPDATE or DELETE a person row (minimal person grant)" do
    email = track_email("immutable@person.example")
    ActiveRecord::Base.connection.execute( # committed as owner
      "INSERT INTO users (name, email, created_at, updated_at) VALUES ('Immutable', '#{email}', now(), now())"
    )
    assert_raises(ActiveRecord::StatementInvalid) do
      @app.execute("UPDATE users SET name = 'x' WHERE email = #{@app.quote(email)}")
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      @app.execute("DELETE FROM users WHERE email = #{@app.quote(email)}")
    end
  end

  # ── a bootstrapped tenant cannot forge a SECOND organization id (WITH CHECK id = GUC) ───────────
  test "cooa_app under one org's GUC cannot INSERT an organization with a different id" do
    org_id = mint_org_id
    in_tenant(org_id) { @app.execute(insert_org(org_id, "legit.example")) }
    assert_raises(ActiveRecord::StatementInvalid, "id must equal the tenant GUC") do
      in_tenant(org_id) { @app.execute(insert_org(SecureRandom.uuid, "forged.example")) }
    end
  end

  private

  def in_tenant(tenant_id, &blk) = TenantContext.with_tenant(tenant_id, connection: @app, &blk)

  def insert_org(id, name)
    "INSERT INTO organizations (id, name, region, created_at, updated_at) " \
      "VALUES ('#{id}', #{@app.quote(name)}, 'JP', now(), now())"
  end

  def mint_org_id
    id = SecureRandom.uuid
    @org_ids << id
    id
  end

  def track_email(email)
    @user_emails << email
    email
  end
end
