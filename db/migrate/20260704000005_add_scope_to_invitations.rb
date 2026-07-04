# Stage 3 (D1 m5): scope an invitation to a single product/component so an accepted membership lands as a
# SCOPED role_assignment (외부 에이전시 = 제품 한정), not tenant-wide. Mirrors the typed-scope shape on
# role_assignments (m1): scope_type + two typed FK columns + a coherence CHECK. Columns default to
# 'tenant'/NULL so every existing (tenant-wide) invitation stays valid — one pending invitation per email
# still holds (the (tenant,email) partial UNIQUE is unchanged; multi-scope = accept then direct grant).
class AddScopeToInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :invitations, :scope_type, :string, null: false, default: "tenant"
    add_column :invitations, :scope_product_id, :bigint
    add_column :invitations, :scope_component_id, :bigint

    # R4 safety_assured: invitations는 소형 pre-prod 테이블(한 자릿수 행). 방금 추가한 nullable FK 컬럼은 전 행
    # NULL → FK 검증이 스캔할 non-null 참조 0건 · CHECK도 기존 행(전부 scope_type='tenant' 기본)이 이미 만족 →
    # validate 잠금이 사실상 무부하. on_delete: :cascade = 부여 대상(제품/구성요소) 삭제 시 대기 초대 자동 정리
    # (고아 방지, ra m1과 동형). add_check_constraint는 자동 역가역(down=remove) → 대칭. (docs/dev-discipline.md R4)
    safety_assured do
      add_foreign_key :invitations, :products,   column: :scope_product_id,   on_delete: :cascade
      add_foreign_key :invitations, :components, column: :scope_component_id, on_delete: :cascade
      add_check_constraint :invitations, <<~SQL.squish, name: "inv_scope_coherence"
        (scope_type = 'tenant'    AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'product'   AND scope_product_id IS NOT NULL AND scope_component_id IS NULL)
        OR (scope_type = 'component' AND scope_product_id IS NULL     AND scope_component_id IS NOT NULL)
      SQL
    end
  end
end
