require "test_helper"

# S5 세션 경계: (1) 살아있는 세션의 token_version bump(logout-everywhere/역할변경/정지) → 다음 쓰기 POST가
# 매요청 revocation 검사(Authentication#verify_revocation)에서 세션 폐기·로그인 리다이렉트되고 부작용 0인지.
# (2) 미로그인 상태의 쓰기 POST 3종이 인증 게이트(resolve_account)에서 로그인 리다이렉트되고 부작용 0인지.
# setup=시드 + 김쿠아(owner) 로그인.
class EdgeSessionTest < ActionDispatch::IntegrationTest
  def v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                 .component_versions.find_by!(version_number: 5)

  test "S5 token_version bump 후 다음 POST → 세션 폐기·로그인 리다이렉트(303)·부작용 없음" do
    kim = Account.find_by!(email: "kim@cooa.dev")
    kim.update_columns(token_version: kim.token_version + 1) # 라이브 세션 무효화(세션엔 옛 버전)

    assert_no_difference "ApprovalRequest.count" do
      post approval_requests_path, params: { component_version_id: v.id }
    end
    assert_response :see_other
    assert_redirected_to new_session_path, "revocation 불일치 → reset_session + 로그인 요구"
  end

  test "S5 미로그인 상태 POST 3종(리뷰요청·초대·grant) → 로그인 리다이렉트(303)·부작용 없음" do
    sign_out
    choi   = Account.find_by!(email: "choi@partner.example")
    co0200 = Product.find_by!(code: "CO0200")

    assert_no_difference [ "ApprovalRequest.count", "Invitation.count", "RoleAssignment.count" ] do
      post approval_requests_path, params: { component_version_id: v.id }
      assert_redirected_to new_session_path

      post invitations_path, params: { email: "x@partner.dev", role_key: "contributor" }
      assert_redirected_to new_session_path

      post role_assignments_path,
           params: { account_id: choi.id, role_key: "external_collaborator", scope_product_id: co0200.id }
      assert_redirected_to new_session_path
    end
  end
end
