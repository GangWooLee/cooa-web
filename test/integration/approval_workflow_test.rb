require "test_helper"

# 버전 리뷰 워크플로(리프레임 — ADR-002 §5.3 후신): 콘텐츠 스냅샷, M2 신원 SoD, stale 경량 가드, 감사.
# 규제 전자서명(step-up)·M-4·하드 M1 차단은 폐지. setup이 시드 + 김쿠아(owner) 로그인 → 새 run의 요청자.
class ApprovalWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                .component_versions.find_by!(version_number: 5)
    post run_screening_component_version_path(@v) # 김쿠아 runs → ScreeningRun(JP)
    @run = @v.screening_runs.order(:created_at).last
  end

  def submit! = post approval_requests_path, params: { screening_run_id: @run.id }
  def request_for = ApprovalRequest.find_by!(screening_run_id: @run.id)

  test "리뷰 요청 → pending (+ 콘텐츠 스냅샷 캡처)" do
    submit!
    req = request_for
    assert_equal "pending", req.status
    assert req.reviewed_content_snapshot_hash.present?
    assert req.reviewed_artifact_digest.present?
  end

  # M1 소프트화: 적격 리뷰어가 없어도 하드 차단(blocked_no_approver)이 아니라 pending — 안내만.
  test "M1 소프트: 적격 리뷰어 부재여도 pending(차단 아님)" do
    RoleAssignment.where(account: User.find_by!(name: "이쿠아").account).delete_all # 유일 리뷰어 제거
    submit!
    assert_equal "pending", request_for.status
  end

  test "M2 SoD: 요청자(김쿠아 owner)는 본인 확인 불가; 이쿠아(리뷰어)는 가능" do
    submit!
    req = request_for
    post confirm_approval_request_path(req) # still 김쿠아
    assert_response :forbidden
    assert_equal "pending", req.reload.status

    lee = Account.find_by!(email: "lee@cooa.dev")
    sign_in_as(lee)
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status
    assert_equal 1, req.approval_steps.count
    assert_equal User.find_by!(name: "이쿠아").id, req.approval_steps.first.approver_id
    assert_equal "confirmed", req.approval_steps.first.decision
  end

  test "stale: 리뷰 요청 후 콘텐츠 변경 시 확인 차단(pending 유지 + deny 감사)" do
    submit!
    req = request_for
    @run.component_version.label_texts.first.update!(content: "CHANGED AFTER REQUEST")
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post confirm_approval_request_path(req)
    assert_equal "pending", req.reload.status, "stale면 확인되면 안 됨"
    assert AuditLog.where(outcome: "deny", denial_reason: "stale_reviewed_tuple").exists?
  end

  test "전이는 감사 로그에 기록(allow)" do
    assert_difference -> { AuditLog.where(action: "submit_for_approval", outcome: "allow").count }, 1 do
      submit!
    end
    req = request_for
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    assert_difference -> { AuditLog.where(action: "confirm_review", outcome: "allow", resource_type: "ApprovalRequest").count }, 1 do
      post confirm_approval_request_path(req)
    end
  end

  test "변경 요청 → changes_requested 스텝 + 감사" do
    submit!
    req = request_for
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post request_changes_approval_request_path(req), params: { reason: "라벨 재작업 필요" }
    assert_equal "changes_requested", req.reload.status
    assert_equal "changes_requested", req.approval_steps.first.decision
  end

  # 버전 뷰가 리뷰 패널을 상태별로 렌더(ERB/정책/아바타 오류 포착)
  test "버전 뷰가 리뷰 패널을 상태별로 렌더" do
    get component_version_path(@v)
    assert_response :success
    assert_match "리뷰 요청", response.body # 요청 전 → 요청 버튼 (김쿠아 owner)
    submit!
    get component_version_path(@v)
    assert_response :success
    assert_match "리뷰 대기", response.body # pending; 김쿠아=요청자 → SoD note
    assert_match "SoD", response.body
  end
end
