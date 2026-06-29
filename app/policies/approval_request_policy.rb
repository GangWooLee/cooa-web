# Identity-based SoD at the approval aggregate (ADR-002 §8.2 / M2): the approver must hold the verb,
# the request must be pending, and the approver must NOT be the submitter (owner included). actor_id is
# the bridged domain user_id (User bigint) — nil (unlinked Account) → fail-CLOSED. C1 staleness + the
# state transition are handled in the controller/service (this policy stays authz-pure).
class ApprovalRequestPolicy < ApplicationPolicy
  def approve?
    can?(:approve) && record.pending? && actor_present? && submitter_distinct?
  end

  def reject?
    can?(:reject) && record.pending? && actor_present? && submitter_distinct?
  end

  private

  def actor_present? = context.actor_id.present?
  def submitter_distinct? = record.submitter_id != context.actor_id
end
