# Stage 2 (D1 m1): scope_id(uuid) is a type mismatch with the bigint domain PKs it must reference
# (products.id / components.id), so a scoped grant can never point at a real row. Replace it with two
# TYPED FK columns + a coherence CHECK that mirrors scope_type. Columns are added NULL (every existing
# grant is scope_type='tenant', 100% scope_id NULL) so the FK + CHECK validate trivially.
class AddTypedScopeToRoleAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :role_assignments, :scope_product_id, :bigint
    add_column :role_assignments, :scope_component_id, :bigint

    # R4 safety_assured: role_assignments는 소형 pre-prod 테이블(수십 행). 방금 추가한 nullable 컬럼은
    # 전 행 NULL → FK 검증이 스캔할 non-null 참조 0건 · CHECK도 기존 행(전부 scope_type='tenant')이 이미
    # 만족 → validate 잠금이 사실상 무부하. on_delete: :cascade = 부여 대상(제품/구성요소) 삭제 시 grant
    # 자동 정리(고아 방지). (docs/dev-discipline.md R4)
    safety_assured do
      add_foreign_key :role_assignments, :products,   column: :scope_product_id,   on_delete: :cascade
      add_foreign_key :role_assignments, :components, column: :scope_component_id, on_delete: :cascade
      add_check_constraint :role_assignments, <<~SQL.squish, name: "ra_scope_coherence"
        (scope_type = 'tenant'    AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'product'   AND scope_product_id IS NOT NULL AND scope_component_id IS NULL)
        OR (scope_type = 'component' AND scope_product_id IS NULL     AND scope_component_id IS NOT NULL)
      SQL
    end
  end
end
