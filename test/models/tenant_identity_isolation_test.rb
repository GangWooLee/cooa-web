require "test_helper"

# A dedicated NON-superuser, NO-BYPASSRLS connection (distinct class so it can coexist with the other RLS
# suites in one process). RLS + the SECURITY DEFINER bridge are only meaningfully proven through a role that
# cannot bypass RLS — the default owner/superuser test connection makes every assertion here vacuous.
class IdentityIsolationAppConnection < ActiveRecord::Base
  self.abstract_class = true
end

# T2 (identity-based tenant resolution) — the DB floor for multi-org coexistence in ONE deployment.
# Proves, under the real cooa_app role (NO BYPASSRLS):
#   (1) the two SECURITY DEFINER auth bridges are the ONLY cross-tenant read path (a normal query
#       fail-CLOSES to 0), and they resolve identity→tenant across orgs with a minimal column surface;
#   (2) once a request adopts a tenant GUC, every other org's rows are invisible (the "B resource → 0 rows"
#       guarantee) and a FORGED session tenant cannot reach the real account (the recheck's DB backstop);
#   (3) an unset tenant GUC is fail-CLOSED (0 rows), never a full-table leak.
class TenantIdentityIsolationTest < ActiveSupport::TestCase
  include CommittedStateCleanup # single-sourced RLS_TABLES/READ_ONLY + leak-proof cleanup (products→…→orgs)

  self.use_transactional_tests = false # cross-connection visibility needs COMMITTED rows

  SHARED_EMAIL = "shared@identity.test".freeze # same person, an UNBOUND active account in BOTH orgs

  setup do
    owner = ActiveRecord::Base.connection
    db = owner.current_database
    owner.execute(%(GRANT CONNECT ON DATABASE "#{db}" TO cooa_app))
    owner.execute("GRANT USAGE ON SCHEMA public TO cooa_app")
    owner.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{RLS_TABLES} TO cooa_app")
    owner.execute("GRANT SELECT ON #{READ_ONLY} TO cooa_app")
    owner.execute("GRANT SELECT ON invitations TO cooa_app") # not in the shared RLS_TABLES subset; needed for the fail-closed probe
    # structure.sql strips GRANTs (pg_dump -x) so the test DB loads the bridges with the default PUBLIC
    # EXECUTE; re-assert the intended cooa_app EXECUTE so the suite is self-contained and grant-explicit.
    owner.execute("GRANT EXECUTE ON FUNCTION auth_lookup_accounts(text, text, text) TO cooa_app")
    owner.execute("GRANT EXECUTE ON FUNCTION auth_lookup_invitation(text) TO cooa_app")

    # Two orgs, committed as the owner (superuser bypasses RLS for setup).
    @org_a = Organization.create!(name: "Ident Tenant A", region: "JP")
    @org_b = Organization.create!(name: "Ident Tenant B", region: "US")

    # A BOUND identity (provider, subject) living only in org A.
    @bound_a = Account.create!(tenant_id: @org_a.id, email: "bound@a.test", status: "active",
                               idp_provider: "google_oauth2", idp_subject: "g-shared-subject")
    # The SAME verified email, UNBOUND + active, in BOTH orgs → the multi-org "org picker" data scenario.
    @unbound_a = Account.create!(tenant_id: @org_a.id, email: SHARED_EMAIL, status: "active")
    @unbound_b = Account.create!(tenant_id: @org_b.id, email: SHARED_EMAIL, status: "active")

    # One domain resource of each new/representative kind per org (row-isolation subjects).
    @prod_a = Product.create!(tenant_id: @org_a.id, name: "P-A", kind: "folder")
    @prod_b = Product.create!(tenant_id: @org_b.id, name: "P-B", kind: "folder")
    @ws_a = Workspace.create!(tenant_id: @org_a.id, name: "WS-A")
    @ws_b = Workspace.create!(tenant_id: @org_b.id, name: "WS-B")

    # A PENDING invitation in org B (cross-tenant token resolution subject), issued by a B-org account.
    @inv_b, @inv_b_raw = tenant_invite(@org_b, "invitee@b.test", inviter_id: @unbound_b.id)
    @digest_b = Invitation.digest(@inv_b_raw)

    cfg = ActiveRecord::Base.connection_db_config.configuration_hash.merge(username: "cooa_app", password: "cooa_dev_pw")
    IdentityIsolationAppConnection.establish_connection(cfg)
    @app = IdentityIsolationAppConnection.connection
  end

  teardown do
    # Cleanup FIRST (leak-proof, per-step isolated), remove the app connection LAST (see rls_isolation_test H2).
    owner = ActiveRecord::Base.connection
    [ @inv_b&.id ].compact.each { |iid| begin; Invitation.where(id: iid).delete_all; rescue StandardError => e; warn "[ident-cleanup] invitation: #{e.class}"; end }
    cleanup_committed_rls_state!([ @org_a&.id, @org_b&.id ])
    IdentityIsolationAppConnection.remove_connection
  end

  # ── (1) the SECURITY DEFINER bridges are the ONLY cross-tenant read path ────────────────────
  test "a plain accounts query under cooa_app with NO tenant GUC is fail-CLOSED (the bridge is necessary)" do
    # Direct SELECT (what the OLD connection-tenant path would have needed) sees nothing without a GUC.
    by_subject = @app.select_value("SELECT COUNT(*) FROM accounts WHERE idp_subject = 'g-shared-subject'").to_i
    by_email   = @app.select_value("SELECT COUNT(*) FROM accounts WHERE email = #{@app.quote(SHARED_EMAIL)}").to_i
    assert_equal 0, by_subject, "no GUC → cooa_app must NOT see the bound account via a normal query"
    assert_equal 0, by_email,   "no GUC → cooa_app must NOT see the unbound accounts via a normal query"
  end

  test "auth_lookup_accounts resolves the BOUND (provider,subject) account and its tenant across orgs" do
    rows = lookup_accounts("google_oauth2", "g-shared-subject", nil) # email nil (unverified path) → bound only
    assert_equal [ [ @bound_a.id, @org_a.id, true ] ],
                 rows.map { |r| [ r["account_id"], r["tenant_id"], bool(r["bound"]) ] }
    assert_equal "Ident Tenant A", rows.first["org_name"], "minimal org label travels for the picker"
  end

  test "auth_lookup_accounts returns the UNBOUND verified-email candidate in EVERY org (picker data)" do
    rows = lookup_accounts("google_oauth2", "no-such-subject", SHARED_EMAIL)
    ids = rows.map { |r| r["account_id"] }.sort
    assert_equal [ @unbound_a.id, @unbound_b.id ].sort, ids, "the same verified email → a candidate per org"
    assert rows.all? { |r| bool(r["bound"]) == false }, "email matches are first-login (unbound) candidates"
    assert_equal [ @org_a.id, @org_b.id ].sort, rows.map { |r| r["tenant_id"] }.sort
  end

  test "auth_lookup_accounts omits UNBOUND candidates when email is absent (unverified-email gate)" do
    rows = lookup_accounts("google_oauth2", "no-such-subject", nil)
    assert_empty rows, "no bound match + no (verified) email → zero candidates"
  end

  test "auth_lookup_accounts excludes non-active unbound accounts from bind candidates" do
    ActiveRecord::Base.connection.execute("UPDATE accounts SET status='suspended' WHERE id='#{@unbound_b.id}'")
    rows = lookup_accounts("google_oauth2", "no-such-subject", SHARED_EMAIL)
    assert_equal [ @unbound_a.id ], rows.map { |r| r["account_id"] }, "a suspended unbound account is not bindable"
  end

  # ── (1b) invitation bridge ──────────────────────────────────────────────────────────────────
  test "auth_lookup_invitation resolves a PENDING invite's tenant across orgs; a plain query is fail-CLOSED" do
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM invitations WHERE token_digest = #{@app.quote(@digest_b)}").to_i,
                 "no GUC → the token is invisible to a normal cooa_app query"
    rows = @app.exec_query("SELECT invitation_id, tenant_id FROM auth_lookup_invitation(#{@app.quote(@digest_b)})").to_a
    assert_equal [ [ @inv_b.id, @org_b.id ] ], rows.map { |r| [ r["invitation_id"], r["tenant_id"] ] }
  end

  test "auth_lookup_invitation ignores revoked/expired tickets (only pending resolve)" do
    ActiveRecord::Base.connection.execute("UPDATE invitations SET revoked_at = now() WHERE id='#{@inv_b.id}'")
    rows = @app.exec_query("SELECT tenant_id FROM auth_lookup_invitation(#{@app.quote(@digest_b)})").to_a
    assert_empty rows, "a revoked ticket must not resolve a tenant"
  end

  # ── (2) once a tenant GUC is adopted, every other org is invisible ──────────────────────────
  # NB: a root product auto-creates a same-named workspace ("루트=작업실 1:1"), so assert by-id VISIBILITY
  # (this org's rows present, the other org's absent) rather than a brittle full-table list.
  test "under org A's GUC, org B's product + workspace rows are invisible (the B-resource → 0 rows guarantee)" do
    in_tenant(@org_a.id) do
      assert_equal 1, count_by_id("products", @prod_a.id),   "A sees its own product"
      assert_equal 1, count_by_id("workspaces", @ws_a.id),   "A sees its own workspace"
      assert_equal 0, count_by_id("products", @prod_b.id),   "A must NOT see B's product"
      assert_equal 0, count_by_id("workspaces", @ws_b.id),   "A must NOT see B's workspace"
    end
    in_tenant(@org_b.id) do
      assert_equal 1, count_by_id("products", @prod_b.id),   "B sees its own product"
      assert_equal 0, count_by_id("products", @prod_a.id),   "B must NOT see A's product"
      assert_equal 0, count_by_id("workspaces", @ws_a.id),   "B must NOT see A's workspace"
    end
  end

  test "a FORGED session tenant cannot reach the real account (the resolve_account recheck's DB backstop)" do
    # An attacker who swaps their session tenant to org B (keeping org A's account_id) runs the request under
    # B's GUC. The account lives in A → invisible under B → resolve_account finds nil → reset+login. Its
    # products are invisible too, so even a leaked id yields nothing.
    in_tenant(@org_b.id) do
      assert_equal 0, @app.select_value("SELECT COUNT(*) FROM accounts WHERE id = #{@app.quote(@unbound_a.id)}").to_i
      assert_equal 0, @app.select_value("SELECT COUNT(*) FROM products WHERE id = #{@app.quote(@prod_a.id)}").to_i
    end
  end

  # ── (3) unset GUC = fail-CLOSED floor ───────────────────────────────────────────────────────
  test "no tenant GUC → products/workspaces/accounts are fail-CLOSED (0 rows, never the whole table)" do
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM products").to_i
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM workspaces").to_i
    assert_equal 0, @app.select_value("SELECT COUNT(*) FROM accounts").to_i
  end

  private

  def in_tenant(tenant_id, &blk) = TenantContext.with_tenant(tenant_id, connection: @app, &blk)

  def count_by_id(table, id) = @app.select_value("SELECT COUNT(*) FROM #{table} WHERE id = #{@app.quote(id)}").to_i

  def lookup_accounts(provider, subject, email)
    @app.exec_query(
      "SELECT account_id, tenant_id, status, bound, org_name, org_region " \
      "FROM auth_lookup_accounts(#{@app.quote(provider)}, #{@app.quote(subject)}, #{@app.quote(email)}) " \
      "ORDER BY tenant_id"
    ).to_a
  end

  def bool(v) = ActiveModel::Type::Boolean.new.cast(v)

  # Build a pending tenant-wide invitation as the owner (RLS bypassed), returning [invitation, raw_token].
  def tenant_invite(org, email, inviter_id:)
    raw = SecureRandom.urlsafe_base64(32)
    inv = Invitation.create!(tenant_id: org.id, email: email, role_key: "contributor", scope_type: "tenant",
                             token_digest: Invitation.digest(raw), expires_at: 7.days.from_now,
                             invited_by_account_id: inviter_id)
    [ inv, raw ]
  end
end
