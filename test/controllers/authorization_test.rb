require "test_helper"

# Controller-level authorization enforcement (Pundit strict + deny → 403), distinct from the
# policy-unit matrix (policy_matrix_test) and the SoD demo (demo_flows ④).
class AuthorizationTest < ActionDispatch::IntegrationTest
  def hero_v(n)
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: n)
  end

  def submit_request_for(v)
    post approval_requests_path(component_version_id: v.id) # 김쿠아 리뷰 요청 → pending (버전 앵커, 스크리닝 불요)
    ApprovalRequest.find_by!(component_version_id: v.id)
  end

  # 박쿠아(scm → contributor)는 리뷰어(approver) 역할이 없어 검토 확인 거부 — SoD 이전에 역할에서 차단.
  test "a contributor cannot confirm a review (role deny, distinct from SoD)" do
    req = submit_request_for(hero_v(5))
    sign_in_as(Account.find_by!(email: "park@cooa.dev")) # scm → contributor (리뷰어 아님)
    post confirm_approval_request_path(req)
    assert_response :forbidden
    assert_equal "pending", req.reload.status, "역할 없는 사용자의 검토 확인은 거부되어야 함"
  end

  # Phase 3a: a Pundit denial is persisted to the append-only audit log (deny spikes = BOLA signal).
  test "a denied action is recorded in the audit log" do
    req = submit_request_for(hero_v(5))
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    assert_difference -> { AuditLog.where(outcome: "deny").count }, 1 do
      post confirm_approval_request_path(req)
    end
    log = AuditLog.where(outcome: "deny").order(:tenant_seq).last
    assert_equal "confirm_review", log.action
    assert_equal "ApprovalRequest", log.resource_type
  end
end
