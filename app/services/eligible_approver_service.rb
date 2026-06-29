# M1 — eligible-approver invariant (ADR-002 §6 note + §8.2). The tenant must have >=1 approve-eligible
# identity DISTINCT from the submitter, or submit_for_approval yields blocked_no_approver (not pending).
# Only `owner` and `approver` carry the `approve` verb (PermissionMatrix) — brand_admin does NOT.
# Runs under the current tenant's RLS context (RoleAssignment is tenant-scoped). scope_id IS NULL =
# tenant-wide (the AssignmentResolver convention; product-scoped grants await scope_id↔domain-id work).
module EligibleApproverService
  ELIGIBLE_ROLES = %w[owner approver].freeze

  module_function

  def eligible_user_ids(market:, exclude_user_id: nil)
    RoleAssignment.active.where(role_key: ELIGIBLE_ROLES, scope_id: nil) # expiry/join pushed to SQL (P4 ①)
                  .where("market IS NULL OR market = ?", market)
                  .joins(:account).distinct.pluck("accounts.user_id")
                  .compact - [exclude_user_id].compact
  end

  def any?(market:, exclude_user_id: nil)
    eligible_user_ids(market: market, exclude_user_id: exclude_user_id).any?
  end
end
