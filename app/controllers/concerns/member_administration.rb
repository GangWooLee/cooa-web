# 멤버 관리(로스터·초대·grant 발급/회수)의 2단 인가(Stage 4 T3). members·invitations·role_assignments가
# 공유한다. 핵심: scoped brand_admin은 조직 레코드로는 인가되지 않으므로(AdminScope 참조) tenant-wide면
# 조직 레코드로 · scoped면 자기 브랜드 제품 레코드로 authorize한다. Pundit verify_authorized는 정직하게
# 충족(skip 없음·policy 메서드 신설 없음)하고, deny는 기존 규약(GET html 303 · 그 외 403 + 감사)을 탄다.
module MemberAdministration
  extend ActiveSupport::Concern

  private

  # 로스터 열람 진입 게이트. tenant_verb = 조직 레벨 verb(index=:list_tenant_accounts?).
  # 반환: AdminScope 결과(:all | [Product,…] | nil). nil이면 조직 authorize가 deny를 낸다(비관리자 차단).
  def authorize_member_read!(tenant_verb)
    scope = Authz::AdminScope.for(current_account)
    if scope.is_a?(Array)
      authorize scope.first, :manage_members? # scoped brand_admin: 자기 브랜드 루트 제품 레코드로(정직)
    else
      authorize current_organization, tenant_verb # :all 통과 · nil은 여기서 deny
    end
    scope
  end

  # 초대·grant 발급/회수의 2단 인가 + 스코프 강제. scoped brand_admin은 "대상 레코드"(작업실=대표 루트 제품 ·
  # 제품=그 제품)로 authorize → 자기 관할 밖이면 roles_on 공집합으로 자연 deny(403), tenant-wide(스코프 없는)
  # 발급은 target=nil → 조직 레코드로 fallback → scoped admin은 tenant-wide manage_members 부재로 deny.
  # :all(tenant-wide admin)은 조직 레코드(스코프 자유·현행 무회귀). 서버측 강제(UI 숨김 무의존).
  def authorize_member_write!(target)
    if Authz::AdminScope.for(current_account).is_a?(Array)
      authorize(target || current_organization, :manage_members?)
    else
      authorize current_organization, :manage_members?
    end
  end

  # 작업실 경로(workspace/product-scope) 발급은 팀 역할 4종만(관리자/멤버/뷰어/외부 협력). 전사 전용 역할
  # (owner·approver·ra_reviewer·assignee)을 스코프에 위조 발급하려는 시도를 서버가 차단한다 — 폼은 4종만
  # 노출하므로 그 외 role_key는 정상 폼으로 도달 불가 = 크래프트된 상승 시도(D4). tenant-scope 발급(전사 초대)은
  # INVITABLE 7종 소관이라 여기서 통과시키고 각 컨트롤러가 별도로 검사(role_assignments는 tenant-scope 자체를 금지).
  # 위반 시 컨트롤러가 R9 flash+redirect로 안내(E3 PRG 소형 폼 — 기존 "부여할 수 없는 역할입니다" 형제와 동일 결).
  def scoped_role_permitted?(scope, role_key)
    scope[:type] == "tenant" || Authz::RoleLabels.workspace_role?(role_key)
  end

  # 초대·grant 파라미터의 스코프 해석(발급 경로). 우선순위: scope_workspace_id > scope_product_id > tenant-wide.
  # 반환 = {type, workspace_id, product_id, target}. target = authorize 대상 레코드(작업실→대표 루트 제품 ·
  # 제품→그 제품 · tenant→nil). 미존재/타테넌트 id는 find가 RecordNotFound(404) — 위조 방어(전역 rescue).
  def resolve_member_scope
    if (wid = params[:scope_workspace_id].presence)
      ws = Workspace.find(wid)
      # workspace: 원본 레코드도 실어 보낸다(즉시추가 분기의 addable 조회 재사용 — 재-find 회피). 하위호환:
      # 기존 소비처는 [:type]/[:workspace_id]/[:product_id]/[:target]만 읽으므로 키 추가는 무해.
      { type: "workspace", workspace_id: ws.id, product_id: nil, target: ws.products.first, workspace: ws }
    elsif (pid = params[:scope_product_id].presence)
      { type: "product", workspace_id: nil, product_id: pid, target: Product.find(pid) }
    else
      { type: "tenant", workspace_id: nil, product_id: nil, target: nil }
    end
  end

  # 스코프된 레코드(초대/grant)의 회수 authorize 대상 = 그 스코프의 대표 제품(작업실→대표 루트 · 제품→그 제품 ·
  # 구성요소→소유 제품). tenant-scope는 nil(회수 경로가 애초에 where.not(scope_type:'tenant')로 배제).
  def scope_authorize_target(record)
    if record.scope_workspace_id
      record.scope_workspace&.products&.first
    elsif record.scope_product_id
      Product.find_by(id: record.scope_product_id)
    elsif record.scope_component_id
      record.scope_component&.product
    end
  end

  # 멤버 관리 액션(초대·grant 발급/회수) 후 복귀 경로. 작업실 페이지에서 왔으면(return_to_workspace=작업실 id)
  # 그 작업실로, 아니면 전사 관리(/members)로 — 발급 링크/알림을 온 자리에서 보여주기 위함(컨텍스트 이탈 없음).
  # workspace_path는 동종 출처 named-route라 오픈 리다이렉트 위험이 없다. 가시 작업실일 때만 그리로(비가시면
  # 전사 관리 폴백) — 인가 경계는 여전히 authorize_member_write!가 강제하며 이 복귀 경로는 표시용일 뿐이다.
  def member_admin_redirect
    wid = params[:return_to_workspace].presence
    return members_path unless wid

    visible_workspaces.any? { |w| w.id.to_s == wid.to_s } ? workspace_path(wid) : members_path
  end

  # 스코프 grant 생성(초대 우회 직접 추가)의 단일 출처. 요청은 이미 RLS 트랜잭션 안이라 uniq_role_assignment_v3
  # 위반이 그 tx를 통째로 abort하면 이후 쿼리가 InFailedSqlTransaction → requires_new(SAVEPOINT)로 격리하고
  # 감사(allow)를 남긴다. RecordInvalid(정합)/RecordNotUnique(중복)은 rescue하지 않는다 — 호출측(role_assignments
  # ·workspace_memberships)이 각자의 R9 문구로 표면화한다(중복 구현 금지 — 생성 로직만 공유).
  def create_scoped_grant!(account_id:, role_key:, scope:)
    grant = RoleAssignment.transaction(requires_new: true) do
      RoleAssignment.create!(
        account_id: account_id, tenant_id: Current.tenant_id, role_key: role_key,
        scope_type: scope[:type], scope_workspace_id: scope[:workspace_id], scope_product_id: scope[:product_id],
        granted_by: current_account.id, granted_at: Time.current
      )
    end
    record_member_audit!("role_assignment.grant", "RoleAssignment",
                         account_id: grant.account_id, role_key: grant.role_key,
                         scope_workspace_id: grant.scope_workspace_id, scope_product_id: grant.scope_product_id)
    grant
  end

  # 스코프 초대 발급의 단일 출처. digest만 저장하므로 raw는 여기서만 존재 → 호출측이 flash[:invite_link]로 1회
  # 노출한다. 감사(allow)를 남긴다. RecordInvalid(이미 멤버·역할 정합)/RecordNotUnique(대기 초대 중복)은 호출측이
  # rescue한다(invitations·workspace_memberships가 각자의 R9 문구로).
  def create_scoped_invitation!(email:, role_key:, scope:)
    # 요청은 이미 RLS 트랜잭션 안(Authentication#scope_to_tenant) — invitations_tenant_open_email_key(대기 초대
    # 중복) 위반이 그 tx를 abort하면 이후 member_admin_redirect의 visible_workspaces 쿼리가 InFailedSqlTransaction.
    # grant 경로와 동형으로 requires_new(SAVEPOINT)로 격리 → 위반은 세이브포인트만 롤백하고 호출측 rescue가 멱등 처리.
    invitation, raw = Invitation.transaction(requires_new: true) do
      Invitation.generate!(
        email: email, role_key: role_key, invited_by_account_id: current_account.id,
        scope_type: scope[:type], scope_workspace_id: scope[:workspace_id], scope_product_id: scope[:product_id]
      )
    end
    record_member_audit!("invitation.create", "Invitation",
                         invitation_id: invitation.id, email: invitation.email, role_key: invitation.role_key,
                         scope_type: invitation.scope_type, scope_workspace_id: invitation.scope_workspace_id,
                         scope_product_id: invitation.scope_product_id)
    [ invitation, raw ]
  end

  # 멤버 관리 감사(초대/grant 발급·회수 공용). resource_id=nil 관례(bigint 도메인 공간 — uuid PK는 after로).
  # 도메인 액터 없는 계정은 AuditLog.record!가 fail-closed raise → 각 액션이 before_action :require_domain_actor로 선차단.
  def record_member_audit!(action, resource_type, **after)
    AuditLog.record!(action: action, resource_type: resource_type, resource_id: nil, outcome: "allow", after: after,
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end
end
