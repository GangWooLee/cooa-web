# WS-track (D1 m-d): scope_workspace_id를 dup-grant 유니크 키와 tenant-wide approver seek 인덱스에 반영.
# uniq_role_assignment_v2(중복 grant 가드)·idx_ra_eligible_approver_v2(tenant-wide = 스코프 3컬럼 전부 NULL)를
# scope_workspace_id 축을 포함한 v3로 CONCURRENTLY 교체(무잠금). v3를 먼저 만든 뒤 v2를 드롭 → 유니크/seek
# 커버리지 연속. tenant-wide 판정 = scope_workspace_id·scope_product_id·scope_component_id 모두 NULL.
class SwapRoleAssignmentWorkspaceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # CONCURRENTLY는 트랜잭션 밖에서만

  def up
    add_index :role_assignments,
              %i[tenant_id account_id role_key scope_workspace_id scope_product_id scope_component_id market],
              unique: true, nulls_not_distinct: true, name: "uniq_role_assignment_v3",
              algorithm: :concurrently
    add_index :role_assignments, %i[tenant_id role_key],
              where: "scope_workspace_id IS NULL AND scope_product_id IS NULL AND scope_component_id IS NULL",
              name: "idx_ra_eligible_approver_v3", algorithm: :concurrently
    remove_index :role_assignments, name: "uniq_role_assignment_v2", algorithm: :concurrently
    remove_index :role_assignments, name: "idx_ra_eligible_approver_v2", algorithm: :concurrently
  end

  def down
    add_index :role_assignments,
              %i[tenant_id account_id role_key scope_product_id scope_component_id market],
              unique: true, nulls_not_distinct: true, name: "uniq_role_assignment_v2",
              algorithm: :concurrently
    add_index :role_assignments, %i[tenant_id role_key],
              where: "scope_product_id IS NULL AND scope_component_id IS NULL",
              name: "idx_ra_eligible_approver_v2", algorithm: :concurrently
    remove_index :role_assignments, name: "uniq_role_assignment_v3", algorithm: :concurrently
    remove_index :role_assignments, name: "idx_ra_eligible_approver_v3", algorithm: :concurrently
  end
end
