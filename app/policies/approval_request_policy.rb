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

  # NOTE (P2 M-4): the approver's MARKET eligibility (role_assignment.market NULL or == record.market) is
  # re-checked in ApprovalRequestsController#approve, not here — it is a DB-backed eligibility (like M1),
  # kept out of this policy so it stays pure/unit-testable. Dormant until market-scoped grants are issued.

  private

  def actor_present? = context.actor_id.present?
  def submitter_distinct? = record.submitter_id != context.actor_id
end
