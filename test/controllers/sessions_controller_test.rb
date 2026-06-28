require "test_helper"

# Local login + per-request revocation (Phase 2a-1). NOTE: the IntegrationTest setup already seeds and
# signs in 김쿠아; tests that need a clean state call sign_out first.
class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "login picker lists demo accounts" do
    sign_out
    get new_session_path
    assert_response :success
    assert_match "이쿠아", response.body
  end

  test "create signs in the chosen account and redirects to root" do
    sign_out
    post session_path, params: { account_id: Account.find_by!(email: "lee@cooa.dev").id }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end

  test "destroy logs out → next request redirects to login" do
    delete session_path
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "unauthenticated request redirects to login" do
    sign_out
    get root_path
    assert_redirected_to new_session_path
  end

  test "token_version bump revokes the live session (ADR-003 §3.3)" do
    Account.find_by!(email: "kim@cooa.dev").bump_token_version!
    get root_path
    assert_redirected_to new_session_path
  end

  test "suspended account is signed out" do
    Account.find_by!(email: "kim@cooa.dev").update!(status: "suspended")
    get root_path
    assert_redirected_to new_session_path
  end

  test "picker is hidden (404) when local login is disabled (production posture)" do
    sign_out
    original = Rails.configuration.x.local_login_enabled
    Rails.configuration.x.local_login_enabled = false
    get new_session_path
    assert_response :not_found
  ensure
    Rails.configuration.x.local_login_enabled = original
  end
end
