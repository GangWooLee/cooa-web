require "test_helper"

# Phase 3b approval workflow (ADR-002 §5.3): C1 reviewed-tuple, M1 eligible-approver, M2 SoD, audit.
# IntegrationTest setup seeds + signs in 김쿠아(owner). A fresh screening run makes 김쿠아 the submitter.
class ApprovalWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                .component_versions.find_by!(version_number: 5)
    post run_screening_component_version_path(@v) # 김쿠아 runs → ScreeningRun(JP)
    @run = @v.screening_runs.order(:created_at).last
  end

  def submit! = post approval_requests_path, params: { screening_run_id: @run.id }
  def request_for = ApprovalRequest.find_by!(screening_run_id: @run.id)

  test "M1: submit with an eligible distinct approver → pending (+ C1 captured)" do
    submit!
    req = request_for
    assert_equal "pending", req.status
    assert req.reviewed_content_snapshot_hash.present?
    assert req.verdict_snapshot.any?
  end

  test "M1: no approver distinct from submitter → blocked_no_approver" do
    RoleAssignment.where(account: User.find_by!(name: "이쿠아").account).delete_all # remove the only approver
    submit!
    assert_equal "blocked_no_approver", request_for.status
  end

  test "M2: submitter (김쿠아, owner) cannot self-approve (SoD); 이쿠아(approver) can" do
    submit!
    req = request_for
    post approve_approval_request_path(req) # still 김쿠아
    assert_response :forbidden
    assert_equal "pending", req.reload.status

    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post approve_approval_request_path(req)
    assert_equal "approved", req.reload.status
    assert_equal 1, req.approval_steps.count
    assert_equal User.find_by!(name: "이쿠아").id, req.approval_steps.first.approver_id
  end

  test "C1: editing reviewed content after submit blocks approval (stale)" do
    submit!
    req = request_for
    @run.component_version.label_texts.first.update!(content: "TAMPERED AFTER SUBMIT")
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post approve_approval_request_path(req)
    assert_equal "pending", req.reload.status, "stale tuple must not approve"
    assert AuditLog.where(outcome: "deny", denial_reason: "stale_reviewed_tuple").exists?
  end

  test "transitions are recorded in the audit log (allow)" do
    assert_difference -> { AuditLog.where(action: "submit_for_approval", outcome: "allow").count }, 1 do
      submit!
    end
    req = request_for
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    assert_difference -> { AuditLog.where(action: "approve", outcome: "allow", resource_type: "ApprovalRequest").count }, 1 do
      post approve_approval_request_path(req)
    end
  end

  test "reject records a rejected step + audit" do
    submit!
    req = request_for
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post reject_approval_request_path(req), params: { reason: "라벨 재작업 필요" }
    assert_equal "rejected", req.reload.status
    assert_equal "rejected", req.approval_steps.first.decision
  end

  # Phase 3c: the screening screen renders the approval panel (catches ERB/policy/avatar errors).
  test "the screening screen renders the approval panel across states" do
    get screening_component_version_path(@v)
    assert_response :success
    assert_match "결재 상신", response.body # no request yet → submit button (김쿠아 owner)
    submit!
    get screening_component_version_path(@v)
    assert_response :success
    assert_match "결재 대기", response.body # pending; 김쿠아=submitter → SoD note, no approve button
    assert_match "SoD", response.body
  end
end
