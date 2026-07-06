require "test_helper"

# T2 (identity-based tenant resolution) at the HTTP layer — the login flow now DISCOVERS the org(s) a
# verified identity belongs to and records session[:tenant_id] so every later request resolves the tenant
# from the SESSION (not the connection/ENV). test=owner (BYPASSRLS) so this suite proves the RESOLUTION +
# BRANCHING + session plumbing; the RLS row-floor is proven separately by tenant_identity_isolation_test.
class MultiOrgIdentityTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    sign_out # the IntegrationTest setup signs in 김쿠아 by default — start each T2 scenario logged out
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  # ── demo path preserved: the dev/test account-picker still resolves the seeded tenant ──────────
  test "account-picker login records the account's tenant in the session" do
    kim = Account.find_by!(email: "kim@cooa.dev")
    post session_path, params: { account_id: kim.id }
    assert_equal kim.tenant_id, session[:tenant_id], "the picker must stamp session[:tenant_id]"
    assert_equal TenantConfig::DEMO_TENANT_ID, session[:tenant_id]
    get root_path
    assert_response :success # resolves the DEMO tenant from the session → dashboard renders
  end

  # ── single org: the OAuth callback stamps the resolved tenant ──────────────────────────────────
  test "OAuth callback signs in and records the discovered tenant in the session" do
    google_callback(uid: "g-kim", email: "kim@cooa.dev")
    assert_redirected_to root_path
    assert_equal TenantConfig::DEMO_TENANT_ID, session[:tenant_id], "tenant comes from discovery, not a claim"
  end

  # ── multi-org: same verified identity in SEVERAL orgs → Slack-style picker ─────────────────────
  test "an identity bound in two orgs is shown an org picker (not silently signed into one)" do
    other = setup_two_org_identity
    google_callback(uid: "g-multi", email: "kim@cooa.dev")
    assert_response :success, "multiple candidates → render the picker, not a redirect"
    assert_match "COOA Demo", response.body
    assert_match other.name, response.body
    assert_nil session[:tenant_id], "no tenant is committed until the user picks one"
  end

  test "picking an org from the multi-org picker completes login into THAT org" do
    other = setup_two_org_identity
    other_acct = Account.find_by!(tenant_id: other.id, idp_subject: "g-multi")
    google_callback(uid: "g-multi", email: "kim@cooa.dev") # renders picker + stashes the verified identity
    post select_organization_path, params: { account_id: other_acct.id }
    assert_redirected_to root_path
    assert_equal other.id, session[:tenant_id], "the session tenant is the CHOSEN org"
    assert_equal other_acct.id, session[:account_id]
  end

  test "the org picker refuses an account_id outside the re-discovered candidate set (no privilege escalation)" do
    setup_two_org_identity
    intruder = Account.find_by!(email: "song@cooa.dev") # a real DEMO account, but NOT bound to g-multi
    google_callback(uid: "g-multi", email: "kim@cooa.dev")
    post select_organization_path, params: { account_id: intruder.id }
    assert_redirected_to new_session_path, "a non-candidate account_id must be rejected"
    assert_nil session[:account_id]
  end

  # ── cross-org invitation: acceptance lands in the INVITE's org, not the demo constant ──────────
  test "a Google user accepting an invite issued by ANOTHER org is onboarded into that org" do
    other = Organization.create!(name: "Invite Org B", region: "US")
    inviter = Account.create!(tenant_id: other.id, email: "owner@b.test", status: "active")
    raw = SecureRandom.urlsafe_base64(32)
    Invitation.create!(tenant_id: other.id, email: "newhire@b.test", role_key: "contributor", scope_type: "tenant",
                       token_digest: Invitation.digest(raw), expires_at: 7.days.from_now,
                       invited_by_account_id: inviter.id)

    get invite_path(raw)
    assert_response :success
    assert_match other.name, response.body, "the landing resolves the invite's org across tenants"

    assert_difference [ "Account.count", "User.count" ], 1 do
      google_callback(uid: "g-newhire", email: "newhire@b.test")
    end
    assert_redirected_to root_path
    acct = Account.find_by!(email: "newhire@b.test")
    assert_equal other.id, acct.tenant_id, "the account is created in the INVITING org, not the demo tenant"
    assert_equal other.id, session[:tenant_id]
  end

  # ── identity re-check: a session tenant that doesn't match its account is rejected ─────────────
  test "a session whose tenant no longer matches its account is bounced to login (recheck defense)" do
    # Sign an account in (session tenant stamped = DEMO), then make its org DIVERGE — modeling a forged or
    # stale session[:tenant_id]. The next request's resolve_account re-check must reset + bounce to login.
    stray_user = User.create!(name: "표류", role: "pm", avatar_color: "#222222", email: "stray@x.test")
    stray = Account.create!(tenant_id: TenantConfig::DEMO_TENANT_ID, user: stray_user, email: "stray@x.test", status: "active")
    post session_path, params: { account_id: stray.id }
    assert_equal TenantConfig::DEMO_TENANT_ID, session[:tenant_id]

    other = Organization.create!(name: "Divergent Org", region: "US")
    stray.update!(tenant_id: other.id) # the account's org now diverges from the session's stamped tenant

    get root_path
    assert_redirected_to new_session_path, "the tenant re-check must reject a session whose account left the tenant"
    assert_nil session[:account_id], "the stale session is cleared (reset_session)"
  end

  # ── audit chain: per-tenant sequences are independent ─────────────────────────────────────────
  test "audit tenant_seq sequences independently per org (each org's first row = seq 1)" do
    org_x = Organization.create!(name: "Seq Org X", region: "JP")
    org_y = Organization.create!(name: "Seq Org Y", region: "US")
    x1 = record_deny(org_x)
    y1 = record_deny(org_y)
    x2 = record_deny(org_x)
    assert_equal [ 1, 1, 2 ], [ x1, y1, x2 ], "each tenant's audit chain starts at 1 and advances independently"
  end

  private

  def google_callback(uid:, email:, verified: true, name: "MultiOrg")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: { email: email, name: name },
      extra: { raw_info: { email_verified: verified } }
    )
    get "/auth/google_oauth2/callback"
  end

  # Bind 김쿠아 (DEMO) to a Google subject AND create a second org whose account carries the SAME subject —
  # i.e. one person is a member of two orgs. Returns the second org.
  def setup_two_org_identity
    Account.find_by!(email: "kim@cooa.dev").update!(idp_provider: "google_oauth2", idp_subject: "g-multi")
    other = Organization.create!(name: "Second Org", region: "US")
    Account.create!(tenant_id: other.id, email: "kim@second.test", status: "active",
                    idp_provider: "google_oauth2", idp_subject: "g-multi")
    other
  end

  def record_deny(org)
    Current.account = nil
    Current.tenant_id = org.id
    AuditLog.record!(action: "probe", resource_type: "X", outcome: "deny").tenant_seq
  end
end
