# WS-track (D1 m-c): role_assignments.scope_workspace_id — 작업실 단위 grant(그 작업실의 모든 루트 서브트리에
# 적용). Stage 2 타입드 스코프(scope_product_id/scope_component_id)에 4번째 축을 더한다. scope_type_check에
# 'workspace' 추가 · ra_scope_coherence 4분기 재작성 · ra_owner_tenant_wide에 ws NULL 추가(owner는 여전히
# tenant-wide 전용). FK는 workspace 삭제 시 grant 연쇄 정리(CASCADE — 부여 대상 소멸 = grant 소멸, ra m1 동형).
class AddWorkspaceScopeToRoleAssignments < ActiveRecord::Migration[8.1]
  def up
    add_column :role_assignments, :scope_workspace_id, :bigint

    # R4 safety_assured: role_assignments는 소형 pre-prod 테이블(수십 행). 방금 추가한 nullable 컬럼은 전 행 NULL
    # → FK 검증 스캔 0건 · 재작성 CHECK도 기존 행(전부 tenant/product/component·scope_workspace_id NULL)이 이미
    # 만족 → validate 잠금이 사실상 무부하. (docs/dev-discipline.md R4)
    safety_assured do
      add_foreign_key :role_assignments, :workspaces, column: :scope_workspace_id, on_delete: :cascade

      remove_check_constraint :role_assignments, name: "role_assignments_scope_type_check"
      add_check_constraint :role_assignments,
                           "(scope_type)::text = ANY ((ARRAY['tenant','workspace','product','component'])::text[])",
                           name: "role_assignments_scope_type_check"

      remove_check_constraint :role_assignments, name: "ra_scope_coherence"
      add_check_constraint :role_assignments, <<~SQL.squish, name: "ra_scope_coherence"
        (scope_type = 'tenant'    AND scope_workspace_id IS NULL     AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'workspace' AND scope_workspace_id IS NOT NULL AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'product'   AND scope_workspace_id IS NULL     AND scope_product_id IS NOT NULL AND scope_component_id IS NULL)
        OR (scope_type = 'component' AND scope_workspace_id IS NULL     AND scope_product_id IS NULL     AND scope_component_id IS NOT NULL)
      SQL

      remove_check_constraint :role_assignments, name: "ra_owner_tenant_wide"
      add_check_constraint :role_assignments,
                           "(role_key)::text <> 'owner' OR (scope_workspace_id IS NULL AND scope_product_id IS NULL AND scope_component_id IS NULL)",
                           name: "ra_owner_tenant_wide"
    end
  end

  def down
    safety_assured do
      remove_check_constraint :role_assignments, name: "ra_owner_tenant_wide"
      add_check_constraint :role_assignments,
                           "(role_key)::text <> 'owner' OR (scope_product_id IS NULL AND scope_component_id IS NULL)",
                           name: "ra_owner_tenant_wide"

      remove_check_constraint :role_assignments, name: "ra_scope_coherence"
      add_check_constraint :role_assignments, <<~SQL.squish, name: "ra_scope_coherence"
        (scope_type = 'tenant'    AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'product'   AND scope_product_id IS NOT NULL AND scope_component_id IS NULL)
        OR (scope_type = 'component' AND scope_product_id IS NULL     AND scope_component_id IS NOT NULL)
      SQL

      remove_check_constraint :role_assignments, name: "role_assignments_scope_type_check"
      add_check_constraint :role_assignments,
                           "(scope_type)::text = ANY ((ARRAY['tenant','product','component'])::text[])",
                           name: "role_assignments_scope_type_check"

      remove_foreign_key :role_assignments, column: :scope_workspace_id
    end
    remove_column :role_assignments, :scope_workspace_id
  end
end
