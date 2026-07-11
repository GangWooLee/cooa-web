class DashboardController < ApplicationController
  # index lists via policy_scope (load_dashboard_rows) rather than authorize — verify the scope instead.
  skip_after_action :verify_authorized, only: :index
  after_action :verify_policy_scoped, only: :index

  # 홈('/') = 작업실 카드 목록. 작업실 진입(/workspaces/:id) 또는 노드 액션(focus/rename/rename_side)이면 그
  # 작업실의 트리 테이블 뷰(복수 루트 수용). 가시성은 policy_scope가 결정 — 비가시 작업실 진입은 redirect(같은
  # 테넌트·비가시) 또는 404(RecordNotFound·타 테넌트/미존재).
  def index
    ws = resolve_index_workspace
    # ws.nil?(홈 카드/가드 경로)이면 cards_only=라이트 프리로드+@rows 스킵, ws 존재(작업실 셸)면 현행 heavy 유지.
    visible = load_dashboard_rows(workspace: ws, cards_only: ws.nil?) # policy_scope 항상 호출(verify_policy_scoped 충족)

    if params[:id].present? && ws.nil? # 명시적 작업실 진입인데 비가시/부재
      raise ActiveRecord::RecordNotFound unless Workspace.exists?(id: params[:id]) # 타 테넌트/미존재 → 404

      return redirect_to root_path, alert: "권한이 없습니다.", status: :see_other # 같은 테넌트·비가시 → 303
    end

    if ws
      @workspace = ws # 작업실 진입 화면 = 트리 테이블 + 작업실 헤더(current_workspace가 @workspace를 소비)
      @workspace_members = workspace_member_accounts(@workspace)
      @can_manage_workspace = manage_members_on_workspace?(@workspace)
      load_workspace_member_admin(@workspace) if @can_manage_workspace # W3: 이 페이지에서 멤버 관리
    else
      @workspace_cards = build_workspace_cards(visible)
      @can_manage_workspaces = policy(current_organization).manage_product? # tenant-wide 관리자 = 새 작업실 생성·이름변경·삭제
      @workspace_member_candidates = workspace_member_candidates if @can_manage_workspaces
    end
  end

  private

  # 새 작업실 생성 폼의 멤버 후보 = tenant-wide grant가 없는 계정(전역 멤버는 이미 전 작업실 접근이라 작업실
  # 멤버로 스코프할 필요 없음). tenant-wide admin만 이 폼을 보므로(생성 게이트) 전 조직의 비-전역 계정을 후보로.
  def workspace_member_candidates
    tenant_wide_ids = RoleAssignment.active.tenant_wide.distinct.pluck(:account_id)
    Account.includes(:user).where.not(id: tenant_wide_ids).order(:created_at)
  end

  # 작업실에 대한 manage_members 권한 — WorkspacePolicy 신설 없이 대표 루트 제품 레코드로 판정(record-dependent
  # 리졸버가 workspace grant를 brand_admin으로 해석 → tenant-wide/자기 작업실 admin은 통과). 빈 작업실은 false.
  def manage_members_on_workspace?(workspace)
    rep = workspace.products.first
    return policy(rep).manage_members? if rep

    # 빈 작업실(대표 제품 없음): record 경로 판정 불가 → tenant-wide manage_members(owner/brand_admin tenant-wide)만.
    # 빈 작업실은 tenant-wide 관리자가 방금 만든 것이므로(생성=tenant-wide 게이트) 첫 제품 생성 전에도 멤버를
    # 초대·관리할 수 있다. 스코프 admin은 빈 상태에선 관리 대상 레코드가 없어 첫 제품 생성으로 표면화(D3).
    policy(current_organization).manage_members?
  end

  # 작업실 페이지의 멤버 관리 데이터(manage_members 보유 시). 전사 관리(/members)로 이탈하지 않고 이 페이지에서
  # 초대·추가·회수·pending을 다룬다(W3). 인가 경계는 초대·grant 컨트롤러가 scope_workspace_id로 재확인 —
  # 여기 데이터는 표시용. AdminScope/subtree_ids 재사용(새 인가 로직 없음). 모두 배치 쿼리라 렌더 N+1 0건.
  def load_workspace_member_admin(workspace)
    subtree_ids = workspace_subtree_ids(workspace)
    @workspace_subtree_ids = subtree_ids.to_set # 뷰의 "이 작업실 소속 RA" 회수 필터에 재사용
    # 이 작업실의 초대 관할 = 작업실-스코프 초대 ∪ 서브트리 제품/구성요소-스코프 초대(둘 다 이 작업실 소속).
    # 대기 목록과 재초대 제안이 이 한 관계를 공유한다(서브트리 필터 단일 정의 — 두 데이터원 드리프트/노출 차단).
    comp_ids = Component.where(product_id: subtree_ids).select(:id)
    subtree_invitations = Invitation.where(
      "scope_workspace_id = :ws OR scope_product_id IN (:pids) OR scope_component_id IN (:cids)",
      ws: workspace.id, pids: subtree_ids, cids: comp_ids
    )
    @workspace_pending = subtree_invitations.pending.order(created_at: :desc)
    # 모달 "사람 추가" 제안 = addable 동료(ⓐ · 즉시 추가) + 과거 초대 재발급 후보(ⓑ). addable 관계는
    # membership 컨트롤러의 즉시추가 분기와 동일 규율(AdminScope.addable_accounts_for) — 표시·서버 판정 일치.
    # 이미 계산한 subtree_ids를 주입해 내부 member_account_ids_for_workspace의 중복 subtree 확장을 재사용.
    @workspace_addable = Authz::AdminScope.addable_accounts_for(current_account, workspace, subtree_ids: subtree_ids)
    # 제안도 pending과 동일 서브트리 관할로 스코프 — 무-스코프면 스코프 admin에게 형제 브랜드 초대 이메일이 노출된다.
    @workspace_invite_suggestions = Invitation.suggestion_emails(subtree_invitations)
  end

  # 진입 대상 작업실(가시) 또는 nil. /workspaces/:id(명시 진입 = 작업실 id) · root_path의 focus/rename/rename_side
  # (노드 액션 = 제품 id → 그 노드의 작업실). 비가시면 nil(명시 진입이면 index가 404/303, 그 외엔 카드로 폴백).
  def resolve_index_workspace
    if (wid = params[:id].presence) # /workspaces/:id — 작업실 직접 진입
      ws = Workspace.find_by(id: wid) or return nil
      return visible_workspaces.find { |w| w.id == ws.id }
    end

    seed_id = params[:focus].presence || params[:rename].presence || params[:rename_side].presence
    return nil unless seed_id

    node = Product.find_by(id: seed_id) or return nil
    workspace_of_node(node)
  end

  # 홈 작업실 카드 — 작업실별 { 작업실, 제품(리프) 수, 스코프 멤버 계정들 }. visible(가시 flat set)로 서브트리를
  # in-memory 그룹핑(쿼리 0) + 스코프 멤버는 한 번에 로드해 작업실로 분배 → per-card N+1 없음(R5). 멀티루트
  # 작업실은 표시 루트 여러 개가 한 작업실 카드로 합쳐진다(제품 수 = 전 루트의 리프 합).
  def build_workspace_cards(visible)
    by_id = visible.index_by(&:id)
    children_of = Hash.new { |h, k| h[k] = [] }
    visible.each { |p| children_of[p.parent_id] << p if by_id.key?(p.parent_id) }

    display_roots = visible.select { |p| p.parent_id.nil? || by_id.exclude?(p.parent_id) }
    roots_by_ws = Hash.new { |h, k| h[k] = [] }
    display_roots.each { |r| (ws = workspace_of_root(r)) && (roots_by_ws[ws.id] << r) }

    members_by_ws = scoped_members_by_workspace(visible, by_id)

    # visible_workspaces = 카드의 권위 목록(빈 작업실 포함·position 순 — D3). 제품 파생 roots/members는 ws.id로 조인.
    visible_workspaces.map do |ws|
      roots = roots_by_ws[ws.id]
      { workspace: ws,
        # 유출 차단 표시명(workspace_label): 실루트 보면 작업실명, 재루팅만 보이면 표시 루트명, 빈 작업실은 작업실명.
        name: workspace_label(ws),
        product_count: roots.sum { |r| count_leaves(r, children_of) },
        members: members_by_ws[ws.id] || [] }
    end
  end

  # 서브트리 리프(kind != folder) 수 = 실제 제품(SKU) 수. children_of(in-memory)로 walk.
  def count_leaves(root, children_of)
    count = 0
    stack = [ root ]
    until stack.empty?
      n = stack.pop
      count += 1 unless n.folder?
      stack.concat(children_of[n.id])
    end
    count
  end

  # 작업실별 스코프 멤버 계정(아바타 요약용). scoped_member_account_ids(배치, tenant-wide 제외)로 계정을 한 번에
  # 얻고, 각 계정의 스코프 grant를 작업실로 분배(in-memory). workspace grant면 그 작업실, product/component grant면
  # 그 제품의 작업실 루트로 귀속. 작업실 멤버 요약(홈 카드)의 단일 정의.
  def scoped_members_by_workspace(visible, by_id)
    member_ids = Authz::AdminScope.scoped_member_account_ids(visible.map(&:id))
    map = Hash.new { |h, k| h[k] = [] }
    return map if member_ids.empty?

    ws_of_product = product_workspace_map(visible, by_id) # 제품 id → 작업실 id(in-memory 루트 walk)
    # 아래 루프는 ra.scope_workspace_id·ra.scope_product_id(자체 컬럼)와 ra.scope_component&.product_id만 읽으므로
    # (스코프명 미렌더) :scope_component만 프리로드하면 충분 — :scope_workspace/:scope_product IN-배치 2건 제거.
    # (셸 멤버 관리 패널의 workspace_member_accounts는 스코프 라벨을 렌더할 수 있어 그쪽 프리로드는 유지.)
    accounts = Account.includes(:user, role_assignments: :scope_component).where(id: member_ids)
    accounts.each do |acc|
      ws_ids = acc.role_assignments.filter_map do |ra|
        next unless ra.active? && !ra.tenant_wide?

        if ra.scope_workspace_id
          ra.scope_workspace_id
        else
          pid = ra.scope_product_id || ra.scope_component&.product_id
          ws_of_product[pid] if pid
        end
      end
      ws_ids.uniq.each { |wid| map[wid] << acc }
    end
    map
  end

  # 가시 제품 id → 그 제품의 작업실 id(가시 집합 내 in-memory 루트 walk). 최상위 가시 조상의 workspace_id —
  # 테넌트-와이드는 실루트라 workspace_id 보유, 스코프 재루팅은 nil(그 경우 카드 소유자 자신의 스코프라 무해).
  def product_workspace_map(visible, by_id)
    visible.each_with_object({}) do |p, h|
      cur = p
      cur = by_id[cur.parent_id] while cur.parent_id && by_id.key?(cur.parent_id)
      h[p.id] = cur.workspace_id
    end
  end
end
