# 버전 리뷰 워크플로(리프레임). 버전 뷰에서 리뷰 요청/확인/변경요청이 여기로 온다. create는 리뷰 요청 +
# 콘텐츠 스냅샷 캡처; confirm은 stale 재검(변경됨→deny) + M2 SoD(정책); 모든 전이는 audit_log 1행(요청 tx와 원자).
# 규제 전자서명(step-up)·M-4 시장관할은 리프레임에서 폐지 — COOA는 규제 사인오프를 발행하지 않는다.
class ApprovalRequestsController < ApplicationController
  # create = 리뷰 요청(screening_run 기준). run의 소유 제품이 verb를 게이트.
  def create
    run = ScreeningRun.find(params[:screening_run_id])
    authorize run, :submit_for_approval?
    req = ApprovalRequest.submit_for!(run, submitter_id: current_account.user_id)
    audit!(req, action: "submit_for_approval", before: nil)
    redirect_back fallback_location: root_path, status: :see_other, notice: submit_notice(req)
  rescue ActiveRecord::RecordNotUnique # 동시 요청 → 멱등, 500 아님
    redirect_back fallback_location: root_path, status: :see_other, notice: "이미 리뷰 요청된 버전입니다."
  end

  def confirm
    req = ApprovalRequest.find(params[:id])
    authorize req, :confirm_review? # M2 SoD(owner 포함) + pending + actor present
    before = req.status
    begin
      req.confirm_review!(reviewer_id: current_account.user_id) # stale 재검은 원자 tx 내부
    rescue ApprovalRequest::StaleReviewedTuple
      audit_stale(req)
      return redirect_back fallback_location: root_path, status: :see_other,
                           alert: "검토 내용이 변경되어 확인할 수 없습니다. 변경 내용을 다시 검토하세요."
    rescue ActiveRecord::RecordNotUnique # 동시 처리 → 이미 결정됨, 500 아님
      return redirect_back fallback_location: root_path, status: :see_other, notice: "이미 처리된 리뷰입니다."
    end
    audit!(req, action: "confirm_review", before: before)
    redirect_back fallback_location: root_path, status: :see_other, notice: "검토 확인되었습니다."
  end

  def request_changes
    req = ApprovalRequest.find(params[:id])
    authorize req, :request_changes?
    before = req.status
    req.request_changes!(reviewer_id: current_account.user_id, reason: params[:reason])
    audit!(req, action: "request_changes", before: before)
    redirect_back fallback_location: root_path, status: :see_other, notice: "변경이 요청되었습니다."
  rescue ActiveRecord::RecordNotUnique # 동시 처리 → 이미 결정됨, 500 아님
    redirect_back fallback_location: root_path, status: :see_other, notice: "이미 처리된 리뷰입니다."
  end

  private

  # 전이 → 감사(allow). 요청 tenant tx와 원자: 실패 시 전이도 롤백(감사 없는 리뷰 없음). action 키
  # (submit_for_approval/confirm_review/request_changes)는 정책 query명과 일치 — deny 감사도 같은 키.
  def audit!(req, action:, before:)
    AuditLog.record!(action: action, resource_type: "ApprovalRequest", resource_id: req.id, outcome: "allow",
                     before: (before ? { "status" => before } : nil), after: { "status" => req.status },
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end

  def audit_stale(req)
    AuditLog.record!(action: "confirm_review", resource_type: "ApprovalRequest", resource_id: req.id,
                     outcome: "deny", denial_reason: "stale_reviewed_tuple",
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end

  # M1 소프트화: 적격 리뷰어(요청자와 구별된 owner/approver) 부재는 차단이 아니라 안내. 리뷰는 요청됨.
  def submit_notice(req)
    if EligibleApproverService.any?(market: req.market, exclude_user_id: req.submitter_id)
      "리뷰 요청이 제출되었습니다."
    else
      "리뷰 요청됨 — 아직 검토 가능한 구성원(요청자와 다른 리뷰어)이 없습니다."
    end
  end
end
