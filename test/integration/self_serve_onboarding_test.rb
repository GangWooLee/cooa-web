require "test_helper"

# T3 (self-serve signup onboarding) at the HTTP layer. A VERIFIED Google identity with NO account anywhere
# (0 candidates) and no valid invitation is no longer rejected — it MINTS its own organization. The callback
# stashes the verified identity (session[:pending_signup]), routes to /onboarding ("name your first
# workspace"), and POST atomically bootstraps org + owner + workspace via OrganizationBootstrap.
#
# test = owner (BYPASSRLS) so this suite proves the BRANCHING + atomicity + session plumbing + isolation of
# the two signup outcomes; the cooa_app RLS/privilege floor (incl. the users INSERT grant the bootstrap
# needs) is proven separately by onboarding_app_connection_test.
class SelfServeOnboardingTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    sign_out # the IntegrationTest setup signs in 김쿠아; every T3 scenario starts logged out
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  # ── a brand-new verified identity is routed to onboarding, NOT rejected ────────────────────────
  test "an unknown verified Google identity is routed to onboarding (0 accounts, no invite)" do
    assert_no_difference [ "Organization.count", "Account.count", "User.count" ] do
      google_callback(uid: "g-founder", email: "founder@newco.example", name: "Founder")
    end
    assert_redirected_to new_onboarding_path, "verified + no account + no invite → onboarding, not reject"
    assert session[:pending_signup]["verified"], "the stash CARRIES the IdP verified fact (data-carrying trust, not a hardcode)"
    follow_redirect!
    assert_response :success
    assert_match "작업실", response.body, "the onboarding page asks for a first workspace name"
  end

  # ── the reject path is PRESERVED for an UNVERIFIED email ───────────────────────────────────────
  test "an UNVERIFIED Google email is still rejected (no onboarding, no org)" do
    assert_no_difference "Organization.count" do
      google_callback(uid: "g-unverified", email: "spoofed@newco.example", verified: false)
    end
    assert_redirected_to new_session_path, "unverified email must not open self-serve onboarding"
    assert_nil session[:pending_signup]
  end

  # ── /onboarding is inaccessible without a pending signup (direct-URL probe) ─────────────────────
  test "GET /onboarding with no pending signup bounces to login" do
    get new_onboarding_path
    assert_redirected_to new_session_path, "onboarding requires a stashed verified identity"
  end

  test "POST /onboarding with no pending signup bounces to login (no org minted)" do
    assert_no_difference "Organization.count" do
      post onboarding_path, params: { workspace_name: "몰래" }
    end
    assert_redirected_to new_session_path
  end

  # ── the full happy path: callback → onboarding form → atomic bootstrap → signed-in owner ────────
  test "completing onboarding atomically creates org + owner + workspace and signs the founder in" do
    google_callback(uid: "g-founder", email: "founder@newco.example", name: "Founder")
    assert_redirected_to new_onboarding_path
    follow_redirect!

    assert_difference [ "Organization.count", "Account.count", "User.count", "Workspace.count", "RoleAssignment.count" ], 1 do
      post onboarding_path, params: { workspace_name: "레티놀 라인" }
    end

    account = Account.find_by!(idp_subject: "g-founder")
    org = Organization.find(account.tenant_id)
    assert_equal org.id, account.tenant_id, "the owner account lives in the newly minted org"
    assert_equal "active", account.status
    assert_equal "google_oauth2", account.idp_provider, "the identity is bound on creation (no separate bind step)"
    assert_equal "founder@newco.example", account.email

    grant = RoleAssignment.find_by!(account_id: account.id)
    assert_equal "owner", grant.role_key
    assert grant.tenant_wide?, "the founding grant is tenant-wide owner (owner_must_be_tenant_wide)"

    ws = Workspace.find_by!(tenant_id: org.id)
    assert_equal "레티놀 라인", ws.name, "the workspace carries the user-supplied name"

    assert_redirected_to workspace_path(ws), "the founder lands in their new (empty) workspace"
    assert_equal org.id, session[:tenant_id], "the session tenant is the new org"
    assert_equal account.id, session[:account_id]
    assert_nil session[:pending_signup], "the pending identity is consumed"

    follow_redirect!
    assert_response :success, "the freshly minted owner can load their empty workspace"
  end

  # ── a blank workspace name is refused (form re-renders, nothing created) ────────────────────────
  test "a blank workspace name does not create an org (form re-renders)" do
    google_callback(uid: "g-founder", email: "founder@newco.example")
    assert_no_difference [ "Organization.count", "Account.count" ] do
      post onboarding_path, params: { workspace_name: "   " }
    end
    assert_response :unprocessable_entity, "a blank name re-renders the onboarding form"
    assert session[:pending_signup].present?, "the pending identity survives a validation bounce (retryable)"
  end

  # ── two independent signups produce two FULLY isolated orgs ─────────────────────────────────────
  test "two separate signups create two completely isolated organizations" do
    google_callback(uid: "g-alice", email: "alice@alpha.example", name: "Alice")
    follow_redirect!
    post onboarding_path, params: { workspace_name: "Alpha WS" }
    org_a = Organization.find_by!(id: session[:tenant_id])
    acct_a = Account.find_by!(idp_subject: "g-alice")
    sign_out

    google_callback(uid: "g-bob", email: "bob@beta.example", name: "Bob")
    follow_redirect!
    post onboarding_path, params: { workspace_name: "Beta WS" }
    org_b = Organization.find_by!(id: session[:tenant_id])
    acct_b = Account.find_by!(idp_subject: "g-bob")

    refute_equal org_a.id, org_b.id, "each signup mints a distinct tenant"
    refute_equal acct_a.id, acct_b.id
    assert_equal org_a.id, acct_a.tenant_id
    assert_equal org_b.id, acct_b.tenant_id
    # each org has exactly ONE workspace + ONE owner grant — no cross-contamination
    assert_equal [ "Alpha WS" ], Workspace.where(tenant_id: org_a.id).pluck(:name)
    assert_equal [ "Beta WS" ],  Workspace.where(tenant_id: org_b.id).pluck(:name)
    assert_equal 1, RoleAssignment.where(tenant_id: org_a.id, role_key: "owner").count
    assert_equal 1, RoleAssignment.where(tenant_id: org_b.id, role_key: "owner").count
    # Bob's live session resolves to Beta and he can reach HIS own workspace. (Row-level cross-tenant
    # invisibility is an RLS guarantee proven under the real cooa_app role — see onboarding_app_connection_test
    # + tenant_identity_isolation_test; this owner-connection suite cannot assert it, BYPASSRLS defeats it.)
    assert_equal org_b.id, session[:tenant_id], "Bob's session tenant is Beta, not Alpha"
    beta_ws = Workspace.find_by!(tenant_id: org_b.id)
    get workspace_path(beta_ws)
    assert_response :success, "Bob can load his own (Beta) workspace"
  end

  # ── invite WINS over self-serve: a valid invite for this identity onboards into the INVITER's org ──
  test "a valid invitation takes precedence over self-serve onboarding (existing branch order preserved)" do
    other = Organization.create!(name: "Inviter Org", region: "US")
    inviter = Account.create!(tenant_id: other.id, email: "owner@inviter.test", status: "active")
    raw = SecureRandom.urlsafe_base64(32)
    Invitation.create!(tenant_id: other.id, email: "hire@inviter.test", role_key: "contributor", scope_type: "tenant",
                       token_digest: Invitation.digest(raw), expires_at: 7.days.from_now,
                       invited_by_account_id: inviter.id)
    get invite_path(raw) # seeds session[:invite_token]

    assert_no_difference "Organization.count" do # the invite consumes the identity — NO new org minted
      google_callback(uid: "g-hire", email: "hire@inviter.test")
    end
    assert_redirected_to root_path, "the invite path signs the hire straight in (not onboarding)"
    assert_equal other.id, session[:tenant_id], "onboarded into the INVITER's org"
    assert_nil session[:pending_signup]
  end

  # ── idempotent re-submit: a POST whose identity was CONCURRENTLY onboarded does NOT mint a 2nd org ──
  test "re-POST after the identity was concurrently onboarded is idempotent (no duplicate org)" do
    google_callback(uid: "g-founder", email: "founder@newco.example")
    assert_redirected_to new_onboarding_path # pending_signup stashed; 0 candidates AT callback time

    # Model the race winner: an account for this identity is committed BETWEEN the callback and this POST
    # (e.g. a double-click's first request). The POST re-discovers it and must sign in, not bootstrap again.
    winner_org  = Organization.create!(name: "Winner Org", region: "JP")
    winner_user = User.create!(name: "Founder", role: "pm", avatar_color: "#8e0300", email: "founder@newco.example")
    Account.create!(tenant_id: winner_org.id, user: winner_user, email: "founder@newco.example", status: "active",
                    idp_provider: "google_oauth2", idp_subject: "g-founder")

    assert_no_difference [ "Organization.count", "Account.count", "Workspace.count" ] do
      post onboarding_path, params: { workspace_name: "Loser WS" }
    end
    assert_redirected_to root_path, "the re-discovered identity is signed in, not bootstrapped a second time"
    assert_equal winner_org.id, session[:tenant_id], "signed into the already-created org"
    assert_nil session[:pending_signup], "the pending identity is consumed either way"

    # The SERVICE is the true concurrency guard (the controller's pre-lock check only covers the sequential
    # case). Calling it DIRECTLY — bypassing that pre-check — exercises the in-lock re-discovery, which hits
    # the REAL auth_lookup_accounts bridge and converges on the already-bound account: an AuthLookup::Candidate,
    # never a second org.
    outcome = nil
    assert_no_difference [ "Organization.count", "Account.count", "Workspace.count" ] do
      outcome = OrganizationBootstrap.call(provider: "google_oauth2", subject: "g-founder",
                                           email: "founder@newco.example", name: "Founder", workspace_name: "In-lock WS")
    end
    assert_instance_of AuthLookup::Candidate, outcome, "in-lock re-discovery returns the existing candidate, not a fresh Result"
    assert_equal winner_org.id, outcome.tenant_id, "converges on the already-created org"
  end

  private

  def google_callback(uid:, email:, verified: true, name: "Founder")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: { email: email, name: name },
      extra: { raw_info: { email_verified: verified } }
    )
    get "/auth/google_oauth2/callback"
  end
end
