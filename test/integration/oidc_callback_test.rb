require "test_helper"

# Phase 2b-1: OIDC callback via OmniAuth.config.test_mode — NO live Keycloak/network. Hits the callback
# path directly (the request phase is POST-CSRF-guarded; test_mode's callback_phase injects the mock).
# test=owner → this suite verifies the SEAM/link/reject/connection-tenant, not RLS (rls_*_test cover RLS).
class OidcCallbackTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    sign_out # the IntegrationTest setup signs in 김쿠아 by default
  end

  teardown do
    OmniAuth.config.mock_auth[:openid_connect] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def auth_callback(provider, uid:, email: nil, name: "OIDC User", email_verified: true, extra: nil)
    raw = { email_verified: email_verified }
    raw.merge!(extra[:raw_info]) if extra && extra[:raw_info]
    hash = { provider: provider.to_s, uid: uid, info: { email: email, name: name }, extra: { raw_info: raw } }
    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new(hash)
    get "/auth/#{provider}/callback"
  end

  def oidc_callback(**kw) = auth_callback(:openid_connect, **kw)

  test "returning user (provider+subject match) signs in" do
    Account.find_by!(email: "lee@cooa.dev").update!(idp_provider: "openid_connect", idp_subject: "kc-lee-sub")
    oidc_callback(uid: "kc-lee-sub", email: "lee@cooa.dev")
    assert_redirected_to root_path
  end

  test "first OIDC login links the seeded account by email and binds the subject (roles preserved)" do
    oidc_callback(uid: "kc-new-sub", email: "lee@cooa.dev", name: "이쿠아")
    assert_redirected_to root_path
    lee = Account.find_by!(email: "lee@cooa.dev")
    assert_equal "kc-new-sub", lee.idp_subject, "first OIDC login binds the IdP subject"
    assert_equal %w[approver ra_reviewer],
                 Authz::RoleResolver::AssignmentResolver.new(lee).roles_on(Product.first).sort,
                 "role_assignments survive the link"
  end

  test "unknown email is rejected" do
    oidc_callback(uid: "kc-x", email: "stranger@evil.test")
    assert_redirected_to new_session_path
  end

  test "unverified email is rejected — no binding (P2 C-1)" do
    oidc_callback(uid: "kc-unv", email: "lee@cooa.dev", email_verified: false)
    assert_redirected_to new_session_path
    assert_nil Account.find_by!(email: "lee@cooa.dev").idp_subject # unbound (seed) stays unbound
  end

  test "an account already bound to another subject is NOT rebound (account-takeover defense, P2 C-1)" do
    Account.find_by!(email: "lee@cooa.dev").update!(idp_provider: "openid_connect", idp_subject: "kc-lee-legit")
    oidc_callback(uid: "kc-attacker", email: "lee@cooa.dev") # verified email, different subject
    assert_redirected_to new_session_path
    assert_equal "kc-lee-legit", Account.find_by!(email: "lee@cooa.dev").idp_subject
  end

  # ── Google 직접 연결 (2026-07-02 개정) — 동일 seam, provider만 다름 ──

  test "Google 최초 로그인: 검증 이메일로 link + (google_oauth2, sub) 바인딩" do
    auth_callback(:google_oauth2, uid: "g-lee-sub", email: "lee@cooa.dev", name: "이쿠아")
    assert_redirected_to root_path
    lee = Account.find_by!(email: "lee@cooa.dev")
    assert_equal "google_oauth2", lee.idp_provider
    assert_equal "g-lee-sub", lee.idp_subject
  end

  test "Google 재방문: (provider, subject) 쌍 매칭으로 로그인" do
    Account.find_by!(email: "lee@cooa.dev").update!(idp_provider: "google_oauth2", idp_subject: "g-lee-sub")
    auth_callback(:google_oauth2, uid: "g-lee-sub", email: "lee@cooa.dev")
    assert_redirected_to root_path
  end

  test "provider 네임스페이스 격리: KC에 바인딩된 subject를 Google이 재사용해도 매칭·재바인딩 불가" do
    Account.find_by!(email: "lee@cooa.dev").update!(idp_provider: "openid_connect", idp_subject: "shared-sub")
    auth_callback(:google_oauth2, uid: "shared-sub", email: "lee@cooa.dev") # 같은 uid, 다른 provider
    assert_redirected_to new_session_path # (google, shared-sub) 미존재 + 이미 바인딩된 계정은 재바인딩 거부
    lee = Account.find_by!(email: "lee@cooa.dev")
    assert_equal "openid_connect", lee.idp_provider, "KC 바인딩이 보존되어야"
  end

  test "Google unverified email은 거부 — 게이트 공유" do
    auth_callback(:google_oauth2, uid: "g-unv", email: "lee@cooa.dev", email_verified: false)
    assert_redirected_to new_session_path
    assert_nil Account.find_by!(email: "lee@cooa.dev").idp_subject
  end

  test "inactive account is rejected" do
    Account.find_by!(email: "park@cooa.dev").update!(status: "suspended")
    oidc_callback(uid: "kc-park", email: "park@cooa.dev")
    assert_redirected_to new_session_path
  end

  test "a token org claim is ignored — tenant comes from the connection" do
    oidc_callback(uid: "kc-kim", email: "kim@cooa.dev",
                  extra: { raw_info: { org_id: "99999999-9999-9999-9999-999999999999" } })
    assert_redirected_to root_path
    assert_equal TenantConfig::DEMO_TENANT_ID, Account.find_by!(email: "kim@cooa.dev").tenant_id
  end

  test "auth failure redirects to login with an alert" do
    get "/auth/failure", params: { message: "invalid_credentials" }
    assert_redirected_to new_session_path
    assert flash[:alert].present?
  end
end
