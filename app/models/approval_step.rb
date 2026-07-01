# 리뷰어의 단일 검토 확인 레코드(리프레임 — "merged-by"식). 전자서명·Part-11 meaning 폐지. 한 요청당
# 한 스텝(단일 확인). Composite FK (tenant_id, approval_request_id) at the DB.
class ApprovalStep < ApplicationRecord
  include TenantScoped

  DECISIONS = %w[confirmed changes_requested].freeze

  belongs_to :approval_request
  belongs_to :approver, class_name: "User"

  validates :decision, inclusion: { in: DECISIONS }
end
