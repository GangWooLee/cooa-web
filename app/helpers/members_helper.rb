module MembersHelper
  # 담당자 지정 드롭다운(표시명부)의 선택지 — 전 도메인 User(표시 정체성). 요청당 1회 메모이즈해 담당자 행마다
  # User 목록을 재쿼리하지 않게 하고(_member_row는 행 수 + 템플릿만큼 렌더됨), :account를 프리로드해 u.name의
  # 표시 리졸버(account-우선)가 유발하는 N+1을 차단한다(R5). 뷰 인스턴스는 부분/루프 간 공유라 인스턴스 변수
  # 메모이즈가 렌더 전체에 걸쳐 유효하다.
  def assignable_member_users
    @assignable_member_users ||= User.includes(:account).order(:id).to_a
  end

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
