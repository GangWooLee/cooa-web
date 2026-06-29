# Approval workflow (Phase 3b/3c, ADR-002 §5.3). The demo screening screen submits/approves here (the
# legacy screening-level approve was retired in 3c). submit (create) captures the C1 reviewed-tuple + runs M1; approve re-validates C1
# (stale → deny) + enforces M2 SoD (policy); every transition is an audit_log row (atomic with the request tx).
class ApprovalRequestsController < ApplicationController
  # create = submit_for_approval from a screening_run; the run's owning product gates the verb.
  def create
    run = ScreeningRun.find(params[:screening_run_id])
    authorize run, :submit_for_approval?
    req = ApprovalRequest.submit_for!(run, submitter_id: current_account.user_id)
    audit!(req, action: "submit_for_approval", before: nil)
    redirect_back fallback_location: root_path, status: :see_other, notice: submit_notice(req)
  rescue ActiveRecord::RecordNotUnique # m-2 (P2): concurrent submit → idempotent, not a 500
    redirect_back fallback_location: root_path, status: :see_other, notice: "이미 상신된 결재입니다."
  end

  def approve
    req = ApprovalRequest.find(params[:id])
    authorize req, :approve? # M2 SoD (owner included) + pending + actor present
    return market_ineligible!(req) unless market_eligible_to_approve?(req) # M-4: jurisdiction re-check
    before = req.status
    begin
      req.approve!(approver_id: current_account.user_id) # C1 staleness re-checked atomically inside (P2 M-2)
    rescue ApprovalRequest::StaleReviewedTuple
      audit_stale(req)
      return redirect_back fallback_location: root_path, status: :see_other,
                           alert: "검토 내용이 변경되어 승인할 수 없습니다. 재스크리닝 후 재제출하세요."
    rescue ActiveRecord::RecordNotUnique # m-2 (P2): concurrent approve → already decided, not a 500
      return redirect_back fallback_location: root_path, status: :see_other, notice: "이미 처리된 결재입니다."
    end
    audit!(req, action: "approve", before: before)
    redirect_back fallback_location: root_path, status: :see_other, notice: "승인되었습니다."
  end

  def reject
    req = ApprovalRequest.find(params[:id])
    authorize req, :reject?
    before = req.status
    req.reject!(approver_id: current_account.user_id, reason: params[:reason])
    audit!(req, action: "reject", before: before)
    redirect_back fallback_location: root_path, status: :see_other, notice: "반려되었습니다."
  rescue ActiveRecord::RecordNotUnique # m-2 (P2): concurrent reject → already decided, not a 500
    redirect_back fallback_location: root_path, status: :see_other, notice: "이미 처리된 결재입니다."
  end

  private

  # Transition → audit (allow). Atomic with the request tenant tx: if this fails, the transition rolls
  # back too (no approval without its audit record). ADR-002 §5.3: transitions ARE audit_log rows.
  def audit!(req, action:, before:)
    AuditLog.record!(action: action, resource_type: "ApprovalRequest", resource_id: req.id, outcome: "allow",
                     before: (before ? { "status" => before } : nil), after: { "status" => req.status },
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end

  def audit_stale(req)
    AuditLog.record!(action: "approve", resource_type: "ApprovalRequest", resource_id: req.id,
                     outcome: "deny", denial_reason: "stale_reviewed_tuple",
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end

  # M-4 (P2): the acting approver must be eligible for THIS request's market (role_assignment.market NULL
  # or == req.market) — the same DB-backed eligibility M1 checked at submit. Kept out of the pure policy so
  # ApprovalRequestPolicy stays unit-testable. Dormant until market-scoped grants are issued (grants=NULL).
  def market_eligible_to_approve?(req)
    EligibleApproverService.eligible_user_ids(market: req.market, exclude_user_id: req.submitter_id)
                           .include?(current_account.user_id)
  end

  def market_ineligible!(req)
    AuditLog.record!(action: "approve", resource_type: "ApprovalRequest", resource_id: req.id,
                     outcome: "deny", denial_reason: "market_ineligible",
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
    head :forbidden
  end

  def submit_notice(req)
    if req.status == "blocked_no_approver"
      "승인 가능한 결재자가 없습니다 — 제출자와 구별된 approver/owner가 필요합니다."
    else
      "승인 요청이 제출되었습니다."
    end
  end
end
