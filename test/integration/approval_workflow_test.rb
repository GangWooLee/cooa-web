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
  def totp_for(account) = ROTP::TOTP.new(account.totp_secret).now # P6 #1: a valid step-up code for the approver

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

    lee = Account.find_by!(email: "lee@cooa.dev")
    sign_in_as(lee)
    post approve_approval_request_path(req), params: { totp_code: totp_for(lee) }
    assert_equal "approved", req.reload.status
    assert_equal 1, req.approval_steps.count
    assert_equal User.find_by!(name: "이쿠아").id, req.approval_steps.first.approver_id
  end

  test "C1: editing reviewed content after submit blocks approval (stale)" do
    submit!
    req = request_for
    @run.component_version.label_texts.first.update!(content: "TAMPERED AFTER SUBMIT")
    lee = Account.find_by!(email: "lee@cooa.dev")
    sign_in_as(lee)
    post approve_approval_request_path(req), params: { totp_code: totp_for(lee) }
    assert_equal "pending", req.reload.status, "stale tuple must not approve"
    assert AuditLog.where(outcome: "deny", denial_reason: "stale_reviewed_tuple").exists?
  end

  test "transitions are recorded in the audit log (allow)" do
    assert_difference -> { AuditLog.where(action: "submit_for_approval", outcome: "allow").count }, 1 do
      submit!
    end
    req = request_for
    lee = Account.find_by!(email: "lee@cooa.dev")
    sign_in_as(lee)
    assert_difference -> { AuditLog.where(action: "approve", outcome: "allow", resource_type: "ApprovalRequest").count }, 1 do
      post approve_approval_request_path(req), params: { totp_code: totp_for(lee) }
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

  # P2 M-4: an approver scoped to another market cannot sign off (jurisdiction). Dormant until
  # market-scoped grants exist (seeds use market=NULL) — this proves the guard once they do.
  test "M-4: an approver scoped to another market cannot approve" do
    submit! # JP request
    req = request_for
    lee = Account.find_by!(email: "lee@cooa.dev")
    lee.role_assignments.update_all(market: "CN") # 이쿠아 now CN-only → not eligible for JP
    sign_in_as(lee)
    post approve_approval_request_path(req)
    assert_response :forbidden
    assert_equal "pending", req.reload.status
  end

  # P6 #1 step-up (TOTP): the signature requires a valid re-auth code bound to the C1 digest.
  test "step-up: approve without a valid TOTP code is refused" do
    submit!
    req = request_for
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post approve_approval_request_path(req) # no code
    assert_equal "pending", req.reload.status, "no signature without re-auth"
    assert AuditLog.where(outcome: "deny", denial_reason: "step_up_failed").exists?
  end

  test "step-up: a valid TOTP records re-auth evidence bound to the C1 digest" do
    submit!
    req = request_for
    lee = Account.find_by!(email: "lee@cooa.dev")
    sign_in_as(lee)
    post approve_approval_request_path(req), params: { totp_code: totp_for(lee) }
    assert_equal "approved", req.reload.status
    step = req.approval_steps.first
    assert step.re_auth_at.present?, "re-auth timestamp recorded"
    assert_equal "totp", step.re_auth_factor
    assert_equal ReviewedTuple.c1_digest(req), step.signed_c1_digest, "signature bound to the exact reviewed tuple"
  end

  test "step-up: an un-enrolled approver is sent to enrollment" do
    submit!
    req = request_for
    lee = Account.find_by!(email: "lee@cooa.dev")
    lee.update!(totp_secret: nil, totp_registered_at: nil) # un-enroll
    sign_in_as(lee)
    post approve_approval_request_path(req)
    assert_redirected_to step_up_path
    assert AuditLog.where(outcome: "deny", denial_reason: "step_up_not_enrolled").exists?
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
