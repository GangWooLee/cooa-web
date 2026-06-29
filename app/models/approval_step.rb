# A single two-eyes approval signature (ADR-002 §5.3) — Part-11 `meaning`. One step per request (launch
# scope; quorum/join-rule deferred). Composite FK (tenant_id, approval_request_id) at the DB.
class ApprovalStep < ApplicationRecord
  include TenantScoped

  DECISIONS = %w[approved rejected].freeze

  belongs_to :approval_request
  belongs_to :approver, class_name: "User"

  validates :decision, inclusion: { in: DECISIONS }
end
