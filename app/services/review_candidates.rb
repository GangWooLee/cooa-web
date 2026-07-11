# 리뷰어 후보 풀(Stage 4 T2 — 두 평면 통합). 후보 판정을 표시 명부(product_member, 자유 역할)에서
# 권한 평면(role_assignment)으로 옮긴다. 후보 = 버전의 "브랜드 루트"(팀 단위) 서브트리에 스코프 grant를
# 가진 계정 ∪ tenant-wide grant 보유 계정의, 연결된 도메인 User(user_id 있는 것만). 단 external_collaborator·
# viewer뿐인 계정은 후보에서 제외한다(users_for 내 근거 주석 — 검토 확인 무결성).
#
# candidate_members(리뷰 패널의 체크박스)와 sanitized_reviewer_ids(서버측 화이트리스트)의 단일 출처 —
# 둘이 같은 집합을 쓰므로 UI에 뜬 후보만 지정 가능하고 임의 id는 걸러진다. product_member는 표시 전용으로
# 남고(담당자 드로어), grant 없는 표시-멤버·미브리지 User는 후보에서 빠진다(의도된 강화·평면 분리).
module ReviewCandidates
  module_function

  # 후보 계정의 연결 User 배열(user_id 있는 것만). exclude_user_id로 제출자/열람자 1인 제외. N+1 없음
  # (하드권한 우선순위 1쿼리 + users 1쿼리 + account 프리로드 = 상수). resolver/product_policy와 동일한
  # "product grant = 서브트리" 의미를 재사용(브랜드 루트의 self_and_descendant_ids · 그 서브트리 컴포넌트).
  def users_for(component_version, exclude_user_id: nil)
    root = component_version.product.brand_root
    product_ids = Product.subtree_ids([ root.id ])
    base = RoleAssignment.active
    rel = base.tenant_wide
              .or(base.where(scope_product_id: product_ids))
              .or(base.where(scope_component_id: Component.where(product_id: product_ids).select(:id)))
    # 작업실 멤버(ws grant) — 이 브랜드 루트가 속한 작업실에 grant를 가진 계정도 후보 풀에 포함(WS-track).
    rel = rel.or(base.where(scope_workspace_id: root.workspace_id)) if root.workspace_id
    # external_collaborator·viewer는 후보 풀에서 뺀다(REF 시나리오 ③: external은 업로드·피드백만, viewer는
    # 읽기 전용 — 둘 다 approve/reject 없음, 리뷰 확인 표면 Segment B 자체가 안 뜸). 후보(=지정 가능)로 두면
    # 지정=소프트그랜트(requested_reviewer ∨ can?(:approve))로 confirm까지 열려 그 설계를 우회 → 규제 검토 확인
    # 무결성 희석. 그래서 이 서브트리에 매칭된 grant 중 이 둘 외의 것이 하나라도 있는 계정만 후보 — grant 행 단위
    # 필터라 "external/viewer + 다른 non-그 역할 병존" 계정은 그 역할 근거로 유지되고, external뿐·viewer뿐인
    # 계정만 제외(자기 스코프 체인에서도). 로스터/멤버 요약(표시 평면)은 이와 무관하게 불변.
    account_ids = rel.where.not(role_key: %w[external_collaborator viewer]).select(:account_id)
    # 후보는 리뷰 패널 체크박스에서 u.name/u.role_short(표시 리졸버 account-우선)로 렌더되므로 :account를 프리로드해
    # 후보 루프의 N+1을 차단한다(R5). user_ids_for(id만 소비) 경로엔 배치 1쿼리 오버헤드뿐 — N+1 아님.
    users = User.includes(:account).where(id: Account.where(id: account_ids).where.not(user_id: nil).select(:user_id))
    users = users.where.not(id: exclude_user_id) if exclude_user_id
    # confirm 하드권한(owner/approver = approve verb) 보유 후보를 앞으로 정렬 — 지정 편의·위계 신호. 집합은 불변,
    # 순서만 바꾼다. 우선순위 집합 = 후보 account 중 active owner/approver grant 보유분(1쿼리). account는 위
    # includes로 프리로드됐으므로 partition은 무-쿼리. Array#partition은 안정적이라 그룹 내 기존(DB) 순서는 보존.
    hard_account_ids = base.where(role_key: %w[owner approver], account_id: account_ids).distinct.pluck(:account_id).to_set
    prioritized, rest = users.to_a.partition { |u| hard_account_ids.include?(u.account&.id) }
    prioritized + rest
  end

  # 화이트리스트 소스 — 후보 User id 배열(제출자 strip은 모델 sync_requested_reviewers!가 담당). users_for의
  # 하드권한-우선 순서를 그대로 물려받지만, 소비처(sanitized_reviewer_ids의 `params & 이것`)는 왼쪽(params)
  # 순서를 보존하는 교집합이라 여기 순서는 화이트리스트 판정에 무관 — 별도 정렬 불요.
  def user_ids_for(component_version) = users_for(component_version).map(&:id)
end
