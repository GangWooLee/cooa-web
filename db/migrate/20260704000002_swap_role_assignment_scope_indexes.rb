# Stage 2 (D1 m2): re-point the two scope_id-bearing indexes at the typed columns, CONCURRENTLY (no
# write lock) so the swap is production-safe. uniq_role_assignment (dup-grant guard) and
# idx_ra_eligible_approver (tenant-wide approver seek) both keyed on scope_id → v2 keyed on the pair.
# Build v2 before dropping v1 so uniqueness/seek coverage is continuous.
class SwapRoleAssignmentScopeIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # CONCURRENTLY cannot run inside a transaction

  def up
    add_index :role_assignments,
              %i[tenant_id account_id role_key scope_product_id scope_component_id market],
              unique: true, nulls_not_distinct: true, name: "uniq_role_assignment_v2",
              algorithm: :concurrently
    add_index :role_assignments, %i[tenant_id role_key],
              where: "scope_product_id IS NULL AND scope_component_id IS NULL",
              name: "idx_ra_eligible_approver_v2", algorithm: :concurrently
    remove_index :role_assignments, name: "uniq_role_assignment", algorithm: :concurrently
    remove_index :role_assignments, name: "idx_ra_eligible_approver", algorithm: :concurrently
  end

  def down
    add_index :role_assignments, %i[tenant_id account_id role_key scope_id market],
              unique: true, nulls_not_distinct: true, name: "uniq_role_assignment",
              algorithm: :concurrently
    add_index :role_assignments, %i[tenant_id role_key],
              where: "scope_id IS NULL", name: "idx_ra_eligible_approver", algorithm: :concurrently
    remove_index :role_assignments, name: "uniq_role_assignment_v2", algorithm: :concurrently
    remove_index :role_assignments, name: "idx_ra_eligible_approver_v2", algorithm: :concurrently
  end
end
