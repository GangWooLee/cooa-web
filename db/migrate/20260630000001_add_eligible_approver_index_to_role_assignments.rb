# P4 ②: EligibleApproverService filters (role_key, scope_id, market) with NO account_id, so neither
# existing index (both have account_id 2nd) can seek role_key → it scans the tenant's role_assignments.
# Partial index on the eligible predicate. No effect at 2a (silo = tens of rows); a 2b/large-tenant hedge.
class AddEligibleApproverIndexToRoleAssignments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # CONCURRENTLY cannot run inside a transaction

  def change
    add_index :role_assignments, [:tenant_id, :role_key],
              where: "scope_id IS NULL", name: "idx_ra_eligible_approver",
              algorithm: :concurrently
  end
end
