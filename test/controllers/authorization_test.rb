require "test_helper"

# Controller-level authorization enforcement (Pundit strict + deny → 403), distinct from the
# policy-unit matrix (policy_matrix_test) and the SoD demo (demo_flows ④).
class AuthorizationTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def hero_v(n)
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: n)
  end

  # 박쿠아(scm → contributor)는 approver 역할이 없어 승인 거부 — SoD 이전에 역할에서 차단.
  test "a contributor cannot approve a screening (role deny, distinct from SoD)" do
    v = hero_v(5)
    post run_screening_component_version_path(v) # submitter = 김쿠아
    park = User.find_by(name: "박쿠아")
    post approve_screening_component_version_path(v, params: { _as: park.id })
    assert_response :forbidden
    refute v.screening_runs.order(:created_at).last.approved?, "역할 없는 사용자의 승인은 거부되어야 함"
  end
end
