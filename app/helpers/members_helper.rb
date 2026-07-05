module MembersHelper
  # 로스터 스코프 배지의 "소속 작업실"(Workspace 엔티티 — 배지 링크용, D5). workspace-scope면 그 작업실,
  # product/component-scope면 그 제품의 작업실(컨트롤러 배치 맵으로 해석). 미해석 시 nil → 뷰가 이름 폴백.
  def workspace_for(role_assignment, workspace_by_id, workspace_id_of)
    if role_assignment.scope_workspace_id
      workspace_by_id[role_assignment.scope_workspace_id] || role_assignment.scope_workspace
    else
      pid = role_assignment.scope_product_id || role_assignment.scope_component&.product_id
      wid = pid && workspace_id_of[pid]
      wid && workspace_by_id[wid]
    end
  end

  # 로스터 스코프 배지의 "소속 작업실" 이름. workspace-scope grant면 그 작업실명, product/component-scope면
  # 그 제품의 작업실(컨트롤러가 배치로 구성한 id_of/by_id 맵으로 해석 — 조상 walk N+1 없음). 미해석 시 스코프
  # 제품/구성요소명으로 폴백(안전).
  def workspace_name_for(role_assignment, workspace_by_id, workspace_id_of)
    if role_assignment.scope_workspace_id
      role_assignment.scope_workspace&.name
    else
      pid = role_assignment.scope_product_id || role_assignment.scope_component&.product_id
      wid = pid && workspace_id_of[pid]
      (wid && workspace_by_id[wid]&.name) ||
        role_assignment.scope_product&.name || role_assignment.scope_component&.display_name
    end
  end
end
