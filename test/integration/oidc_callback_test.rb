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
    OmniAuth.config.test_mode = false
  end

  def oidc_callback(uid:, email: nil, name: "OIDC User", extra: nil)
    hash = { provider: "openid_connect", uid: uid, info: { email: email, name: name } }
    hash[:extra] = extra if extra
    OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(hash)
    get "/auth/openid_connect/callback"
  end

  test "returning user (idp_subject match) signs in" do
    Account.find_by!(email: "lee@cooa.dev").update!(idp_subject: "kc-lee-sub")
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
