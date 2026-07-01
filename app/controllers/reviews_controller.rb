# "내게 요청된 리뷰" 수신함 — 내가 지정 리뷰어인 pending 요청(제품 넘나듦). RLS가 테넌트 격리,
# policy_scope로 스코프 검증(대시보드 패턴). status 인덱스 + arr_tenant_reviewer_idx 활용.
class ReviewsController < ApplicationController
  skip_after_action :verify_authorized, only: :index
  after_action :verify_policy_scoped, only: :index

  def index
    # reviewer_id 필터 + 유니크 인덱스 → 요청당 조인 1행이라 .distinct 불요.
    @requests = policy_scope(ApprovalRequest)
                  .where(status: "pending")
                  .joins(:approval_request_reviewers)
                  .where(approval_request_reviewers: { reviewer_id: current_user.id })
                  .includes(:submitter, component_version: { component: :product })
  end
end
