# Stage 2 (D1 m3): drop the dead scope_id column. All app references migrated to the typed columns
# (D1b: tenant_wide scope, owner_grant?, eligible/last-owner/account/invitation/seeds), and m2 removed
# the last indexes on it. An IN-MIGRATION guard (stronger than a CI check) aborts if any non-NULL value
# ever appeared, so the drop can never silently discard a real scope.
class DropRoleAssignmentScopeId < ActiveRecord::Migration[8.1]
  def up
    RoleAssignment.reset_column_information
    if RoleAssignment.where.not(scope_id: nil).exists?
      raise "scope_id에 non-NULL 존재 — 수동 확인 필요(typed 컬럼 백필 선행 후 재시도)"
    end

    # R4 safety_assured: scope_id는 실측 100% NULL + 위 가드로 재확인, 모든 앱 참조가 typed 컬럼으로
    # 이전됨(Stage 2 D1b), 구 인덱스는 m2에서 제거 완료(잔여 의존 0), 소형 pre-prod 테이블.
    # (docs/dev-discipline.md R4)
    safety_assured { remove_column :role_assignments, :scope_id }
  end

  def down
    add_column :role_assignments, :scope_id, :uuid
  end
end
