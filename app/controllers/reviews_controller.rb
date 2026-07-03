# 리뷰 인박스(투-세그먼트). A: 내게 요청된 리뷰(내가 지정 리뷰어인 pending). B: 리뷰어 미배정 — 내가 맡을 수
# 있는 리뷰(적격 owner/approver에게만). RLS가 테넌트 격리, policy_scope로 스코프 검증(대시보드 패턴).
class ReviewsController < ApplicationController
  skip_after_action :verify_authorized, only: :index
  after_action :verify_policy_scoped, only: :index

  def index
    # Segment A: reviewer_id=me. 유니크 인덱스 → 요청당 조인 1행이라 .distinct 불요.
    @assigned = policy_scope(ApprovalRequest)
                  .where(status: "pending")
                  .joins(:approval_request_reviewers)
                  .where(approval_request_reviewers: { reviewer_id: current_user.id })
                  .includes(:submitter, component_version: { component: :product })

    # 적격 판정은 1회(레코드별 policy 호출 금지 — AssignmentResolver의 record-independent N+1 함정 회피).
    @eligible = current_user && EligibleApproverService.eligible_user_ids.include?(current_user.id)
    return unless @eligible

    # Segment B: pending · 내가 요청자 아님(SoD) · 지정 리뷰어 없음(미배정).
    unassigned = policy_scope(ApprovalRequest)
                   .where(status: "pending")
                   .where.not(submitter_id: current_user.id)
                   .where.missing(:approval_request_reviewers)
                   .includes(:submitter, component_version: { component: :product })
                   .order(requested_at: :asc)
    @inbox = ReviewInboxPresenter.new(unassigned: unassigned,
                                      products: policy_scope(Product.all), brand_filter: params[:brand])
  end
end
