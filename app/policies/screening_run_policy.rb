# Identity-based Separation of Duties (ADR-002 §8.2 / §16): the approver must hold the role AND
# must NOT be the submitter — owner is NOT exempt (M2). Phase 1 uses ScreeningRun.requested_by_id as
# the submitter; Phase 3 promotes this to approval_request.submitter_id with the full state machine
# (eligible-approver invariant, blocked_no_approver, reviewed_* re-validation).
class ScreeningRunPolicy < ApplicationPolicy
  def approve?
    can?(:approve) && submitter_distinct?
  end

  def reject?
    can?(:reject) && submitter_distinct?
  end

  private

  def submitter_distinct?
    record.requested_by_id.present? && record.requested_by_id != context.actor_id
  end
end
