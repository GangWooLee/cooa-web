require "test_helper"

# Controller-level authorization enforcement (Pundit strict + deny → 403), distinct from the
# policy-unit matrix (policy_matrix_test) and the SoD demo (demo_flows ④).
class AuthorizationTest < ActionDispatch::IntegrationTest

  def hero_v(n)
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: n)
  end

  # 박쿠아(scm → contributor)는 approver 역할이 없어 승인 거부 — SoD 이전에 역할에서 차단.
  test "a contributor cannot approve a screening (role deny, distinct from SoD)" do
    v = hero_v(5)
    post run_screening_component_version_path(v) # submitter = 김쿠아(기본 로그인)
    sign_in_as(Account.find_by!(email: "park@cooa.dev")) # scm → contributor (approver 아님)
    post approve_screening_component_version_path(v)
    assert_response :forbidden
    refute v.screening_runs.order(:created_at).last.approved?, "역할 없는 사용자의 승인은 거부되어야 함"
  end

  # Phase 3a: a Pundit denial is persisted to the append-only audit log (deny spikes = BOLA signal).
  test "a denied action is recorded in the audit log" do
    v = hero_v(5)
    post run_screening_component_version_path(v)
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    assert_difference -> { AuditLog.where(outcome: "deny").count }, 1 do
      post approve_screening_component_version_path(v)
    end
    log = AuditLog.where(outcome: "deny").order(:tenant_seq).last
    assert_equal "approve", log.action
    assert_equal "ScreeningRun", log.resource_type
  end
end
