# WS-track (D1 m-e): invitations.scope_workspace_id — 작업실 단위 초대(수락 시 workspace-scope role_assignment로
# 관통). role_assignments(m-c)의 타입드 스코프 형태를 그대로 미러. inv_scope_coherence 4분기 재작성 · FK는
# workspace 삭제 시 대기 초대 연쇄 정리(CASCADE). (tenant,email) 부분 유니크는 불변 — 이메일당 대기 초대 1건.
class AddWorkspaceScopeToInvitations < ActiveRecord::Migration[8.1]
  def up
    add_column :invitations, :scope_workspace_id, :bigint

    # R4 safety_assured: invitations는 소형 pre-prod 테이블(한 자릿수 행). 방금 추가한 nullable FK 컬럼은 전 행 NULL
    # → FK 검증 스캔 0건 · 재작성 CHECK도 기존 행(전부 scope_type='tenant' 기본·ws NULL)이 이미 만족 → 무부하.
    safety_assured do
      add_foreign_key :invitations, :workspaces, column: :scope_workspace_id, on_delete: :cascade

      remove_check_constraint :invitations, name: "inv_scope_coherence"
      add_check_constraint :invitations, <<~SQL.squish, name: "inv_scope_coherence"
        (scope_type = 'tenant'    AND scope_workspace_id IS NULL     AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'workspace' AND scope_workspace_id IS NOT NULL AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'product'   AND scope_workspace_id IS NULL     AND scope_product_id IS NOT NULL AND scope_component_id IS NULL)
        OR (scope_type = 'component' AND scope_workspace_id IS NULL     AND scope_product_id IS NULL     AND scope_component_id IS NOT NULL)
      SQL
    end
  end

  def down
    safety_assured do
      remove_check_constraint :invitations, name: "inv_scope_coherence"
      add_check_constraint :invitations, <<~SQL.squish, name: "inv_scope_coherence"
        (scope_type = 'tenant'    AND scope_product_id IS NULL     AND scope_component_id IS NULL)
        OR (scope_type = 'product'   AND scope_product_id IS NOT NULL AND scope_component_id IS NULL)
        OR (scope_type = 'component' AND scope_product_id IS NULL     AND scope_component_id IS NOT NULL)
      SQL

      remove_foreign_key :invitations, column: :scope_workspace_id
    end
    remove_column :invitations, :scope_workspace_id
  end
end
