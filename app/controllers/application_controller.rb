class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pundit::Authorization
  # Auth (ADR-003 · T2 identity-based tenant): scope_to_tenant(open the session-tenant RLS tx) → resolve_account
  # (load + re-check the account belongs to the session tenant + revocation/idle). See concerns/authentication.
  include Authentication

  helper_method :header_tabs, :pending_review_count, :overdue_review_count, :visible_product_id_set, :can_view_members?,
                :current_workspace, :current_workspace_label, :workspace_label, :visible_workspaces, :context_tree_roots

  # Strict Pundit (ADR-002 §0 BOLA defense): every action must authorize (or explicitly skip_authorization).
  # verify_policy_scoped is enabled per-controller for index-like actions (DashboardController) — referencing
  # :index here would raise on controllers without an :index action (raise_on_missing_callback_actions).
  after_action :verify_authorized
  rescue_from Pundit::NotAuthorizedError, with: :deny_access
  # 전역 rescue 계층(E1 · docs/error-handling.md): 리소스 조회 실패 → 404, 파라미터 누락 → 400. html이면
  # 정적 브랜드 페이지(public/*.html) 렌더, 그 외(JSON/Turbo Stream)는 본문 없이 상태코드만. RecordInvalid는
  # 전역 rescue하지 않는다 — 폼마다 표준이 다르다(파일 업로드=인라인 422 · PRG 소형 폼=flash alert).
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  # Pundit "user" = role-resolution context: the authenticated Account (roles via AssignmentResolver).
  def pundit_user = Authz::AccessContext.new(actor: Current.account)

  def current_organization = Organization.find(Current.tenant_id)

  # 멤버 로스터 진입권(사이드바 "멤버" 링크 가시성 · Stage 4 T3). tenant-wide list_tenant_accounts 보유자
  # (읽기 — lee 등 ra/approver 무회귀) OR scoped brand_admin(자기 브랜드). scoped admin은 조직 레벨
  # list_tenant_accounts?를 통과하지 못하므로(AdminScope 트랩) AdminScope 존재로 별도 판정. 요청당 메모이즈.
  def can_view_members?
    return @can_view_members if defined?(@can_view_members)

    @can_view_members = !!Current.account &&
                        (policy(current_organization).list_tenant_accounts? || !Authz::AdminScope.for(Current.account).nil?)
  end

  # 도메인 액터(연결된 User) 없는 계정은 감사(allow)를 남기는 도메인 쓰기를 수행할 수 없다 — actor가 nil이면
  # AuditLog.record!가 fail-closed로 raise해 500이 된다. 그 전에 fail-closed 403으로 막는 공용 가드(E4 통일).
  # before_action이라 authorize보다 먼저 돌지만, 미브리지 계정은 어차피 도메인 쓰기 불가라 순서는 무해하고
  # (halt 시 after_action verify_authorized는 실행되지 않음), bridged 계정은 그대로 통과해 정상 authorize된다.
  def require_domain_actor
    head :forbidden if current_account&.user_id.blank?
  end

  # 전역 rescue 렌더(E1). html = 정적 브랜드 페이지 파일 렌더(레이아웃·asset 파이프라인 무의존),
  # 그 외 포맷 = 본문 없는 상태코드만(fetch/Turbo 소비자에 HTML 404 본문을 떠넘기지 않음).
  def render_not_found(_error) = render_static_error(:not_found)
  def render_bad_request(_error) = render_static_error(:bad_request)

  def render_static_error(status)
    if request.format.html?
      code = Rack::Utils::SYMBOL_TO_STATUS_CODE[status]
      render file: Rails.public_path.join("#{code}.html"), status: status, layout: false, content_type: "text/html"
    else
      head status
    end
  end

  # deny → 403 for mutations/non-html (anti-enumeration; RLS already 404s other tenants' rows),
  # redirect+alert for GET html. Persistent audit_log row = Phase 3 (Phase 1 = structured log).
  def deny_access(exception)
    Rails.logger.warn("[authz][deny] verb=#{exception.query} record=#{exception.record.class} account=#{Current.account&.id} tenant=#{Current.tenant_id}")
    audit_deny(exception)
    if request.get? && request.format.html?
      redirect_to root_path, alert: "권한이 없습니다.", status: :see_other
    else
      head :forbidden
    end
  end

  # Persist the denial (ADR-002 §5.4 — deny spikes signal BOLA probing). Best-effort: an audit failure
  # must never turn a clean 403 into a 500.
  def audit_deny(exception)
    return if Current.tenant_id.blank? # deny before tenant context — nothing to scope to; logged above
    record = exception.record
    klass = record.is_a?(Class) ? record : record.class
    # rescue_from runs AFTER the around_action RLS tx has unwound, so app.current_tenant_id is cleared.
    # Re-establish it in a fresh tenant tx — otherwise the INSERT fails RLS WITH CHECK under cooa_app and
    # the deny is silently lost in production (P2 M-1). Still best-effort (a failure must not 500 a 403).
    TenantContext.with_tenant(Current.tenant_id) do
      AuditLog.record!(
        action: exception.query.to_s.delete_suffix("?"),
        resource_type: klass.name,
        resource_id: (record.try(:id) unless record.is_a?(Class)),
        outcome: "deny", denial_reason: "pundit",
        request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent
      )
    end
  rescue => e
    Rails.logger.error("[audit] deny logging failed: #{e.class}: #{e.message}")
  end

  # ── 작업실(Workspace) 컨텍스트 (WS-track, 2026-07-05) ─────────────────────────
  # 작업실 = Workspace 엔티티(복수 루트를 담는 상위 컨테이너). 사이드바가 매 페이지 렌더하므로 컨텍스트는
  # **렌더 시점 lazy**로 도출한다(header_tabs와 동일 이유). 진실원천 1곳: 홈 카드(W1)·컨텍스트 사이드바(W2) 공용.
  #
  # 계약(2026-07-05 F1): current_workspace = (dashboard#index가 세팅한 @workspace)
  #                    ?? (@product 등 **현재 화면 리소스**에서 도출한 가시 작업실) ?? nil.
  # 컨텍스트는 오직 현재 화면의 리소스에서 도출한다 — 직전 작업실을 세션에 저장했다가 리소스 없는 글로벌
  # 화면(인박스·전사관리)에서 되살리지 않는다. 되살리면 사이드바는 떠난 작업실 트리를, 본문(셸)은 그 작업실
  # 데이터를 표시해 "리소스↔컨텍스트 분열"이 난다(F1 결함의 잔여 축). 글로벌 화면 = 항상 컨텍스트 해제(nil).
  # 이 계약은 shared/_sidebar 헤더 주석(컨텍스트 안=리소스 있음 / 밖=홈·인박스·전사관리)과 삼위일치한다.
  def current_workspace
    return @current_workspace if defined?(@current_workspace)

    @current_workspace = resolve_current_workspace
  end

  def resolve_current_workspace
    return nil unless nav_ready? && Current.tenant_id

    # 1) dashboard#index가 세팅한 Workspace 엔티티 우선.
    return @workspace if defined?(@workspace) && @workspace

    # 2) 리소스 도출 — 상세/버전/스크리닝/비교가 세팅하는 @product의 가시 작업실(비가시면 nil).
    return workspace_of_node(@product) if defined?(@product) && @product

    # 3) 그 외(인박스·전사관리 등 리소스 없는 글로벌 화면) = 컨텍스트 해제. 세션에 직전 작업실을 저장·복원하지
    #    않는다(위 계약) — 컨텍스트는 오직 위 두 리소스 축에서만 산다.
    nil
  end

  # 노드의 최상위 **가시** 조상 = 그 노드가 속한 (가시) 표시 루트 Product. 테넌트-와이드는 실제 트리 루트,
  # 스코프 계정은 재루팅된 가시 루트(비가시 조상 브랜드명 유출 차단). 단일 노드라 N+1 무관.
  def topmost_visible_ancestor(product)
    return nil unless product

    chain = product.self_and_ancestors # [루트 … self]
    set = visible_product_id_set
    visible_chain = set ? chain.select { |a| set.include?(a.id) } : chain
    visible_chain.first
  end

  # 노드가 속한 가시 작업실(비가시면 nil). 가시 표시 루트를 얻고 그 작업실을 도출.
  def workspace_of_node(product)
    root = topmost_visible_ancestor(product)
    root && workspace_of_root(root)
  end

  # 표시 루트 → 작업실. 실루트(부모 nil)면 자신의 workspace, 재루팅(부모 비가시)이면 brand_root의 workspace
  # (같은 테넌트라 RLS로 조상 로드 가능 — 스코프 격리는 policy 레이어 담당). N+1은 컨트롤러가 루트만 배치.
  def workspace_of_root(root)
    root.parent_id.nil? ? root.workspace : root.brand_root.workspace
  end

  # 가시 표시 루트(가시 제품 중 부모가 비가시/nil) — 작업실 목록·라벨의 단일 소스(요청당 1회 로드).
  def visible_display_roots
    @visible_display_roots ||= visible_roots(Product.includes(:parent, :workspace))
  end

  # 컨텍스트 없음 사이드바 + 홈 카드의 작업실 목록 = 가시 표시 루트가 속한 작업실 ∪ 직접 가시한 작업실(빈 작업실
  # 포함 — D3). 중복 제거(id)·position 순. 빈 작업실은 제품 파생 목록에 안 잡히므로 directly_visible_workspaces가 보완.
  def visible_workspaces
    @visible_workspaces ||= (visible_display_roots.filter_map { |r| workspace_of_root(r) } + directly_visible_workspaces)
                            .uniq(&:id).sort_by { |w| [ w.position || 0, w.id ] }
  end

  # 제품과 무관하게 직접 가시한 작업실(빈 작업실도 포함). tenant-wide/데모는 전 작업실을, 스코프 계정은
  # workspace-scope grant를 가진 작업실을 본다. 제품 파생 목록과 합쳐 갓 만든 빈 작업실이 홈 카드·사이드바·진입
  # 판정(resolve_index_workspace)에서 보이게 한다. product-scope만 가진 계정은 빈 작업실 직접 가시 없음(무회귀).
  def directly_visible_workspaces
    if visible_product_id_set.nil?
      Workspace.all.to_a # tenant-wide / 데모 User → 전 작업실
    elsif Current.account
      ws_ids = RoleAssignment.active.where(account_id: Current.account.id)
                             .where.not(scope_workspace_id: nil).distinct.pluck(:scope_workspace_id)
      ws_ids.any? ? Workspace.where(id: ws_ids).to_a : []
    else
      []
    end
  end

  # 작업실 표시명 맵(D3 유출 차단): 이 계정이 작업실의 **실루트**(부모 nil)를 보면 작업실명, 재루팅만 보이면
  # (리프 스코프) 볼 수 있는 표시 루트의 이름. 비가시 조상 작업실명이 새어나가지 않게 라벨을 클립한다
  # (브레드크럼 조상 라벨 클리핑과 동일 원리 — visible_product_id_set). 요청당 1회.
  def visible_workspace_labels
    @visible_workspace_labels ||= visible_display_roots.group_by { |r| workspace_of_root(r) }
                                                       .each_with_object({}) do |(ws, rs), h|
      next unless ws

      h[ws.id] = rs.any? { |r| r.parent_id.nil? } ? ws.name : rs.first.name
    end
  end

  # 작업실 → 유출 차단 표시명(맵 미스 시 작업실명 폴백 — tenant-wide는 항상 작업실명).
  def workspace_label(workspace) = workspace && (visible_workspace_labels[workspace.id] || workspace.name)

  # 현재 작업실의 유출 차단 표시명(사이드바 헤더·작업실 페이지 헤더 공용).
  def current_workspace_label = workspace_label(current_workspace)

  # 컨텍스트 있음 사이드바의 트리 = **현재 작업실의 모든 가시 루트**(복수 루트 수용). 가시 전체를 :children
  # 프리로드로 1회 로드(하위 children 프리로드 → _tree_node 재귀 N+1 0건) 그중 현재 작업실 소속 표시 루트만 렌더.
  def context_tree_roots
    ws = current_workspace
    return [] unless ws

    @context_tree_roots ||= visible_roots(Product.includes(:children, :parent, :workspace))
                            .select { |r| workspace_of_root(r)&.id == ws.id }
  end

  # 표시 루트 = 가시 제품 중 부모가 비가시(또는 nil)인 노드 (Stage 2 D3). 테넌트-와이드 액터면 Product.roots와
  # 동일(무회귀). 스코프 한정 계정이면 부여 서브트리를 최상위로 끌어올리되 비가시 조상은 렌더하지 않음(브랜드명
  # 유출 차단). policy_scope가 가시집합을 결정 → 그 안에서 부모가 비가시인 노드만 루트. tree_preorder 재사용.
  def visible_roots(base)
    visible = policy_scope(base).to_a
    ids = Set.new(visible.map(&:id))
    visible.select { |p| p.parent_id.nil? || ids.exclude?(p.parent_id) }
           .sort_by { |p| [ p.position || 0, p.id ] }
  end

  # Request-memoized visible product-id Set for visibility-aware ANCESTOR rendering (breadcrumb /
  # data-node-path clip — Stage 2 D3 브랜드명 유출 차단). nil = "all products visible" (tenant-wide / demo
  # User): callers skip clipping (no regression). Reuses ProductPolicy::Scope so the visible set that scopes
  # dashboard rows and the set that clips ancestor labels are ONE source. Not routed through Pundit's
  # policy_scope → does not perturb verify_policy_scoped tracking.
  def visible_product_id_set
    return @visible_product_id_set if defined?(@visible_product_id_set)

    ids = ProductPolicy::Scope.visible_ids_or_all(pundit_user)
    @visible_product_id_set = ids&.to_set
  end

  # 상단 히스토리 탭 — 렌더 시점에 계산해야 함. set_nav(before_action)는 액션의 TabHistory.track보다
  # 먼저 실행되므로 거기서 계산하면 "들어간 페이지"의 탭이 한 스텝 늦게 보임. 렌더 시점엔 track 이후라
  # 현재 항목이 포함됨(들어간 즉시 표시). lazy 메모이즈로 요청당 1회.
  def header_tabs
    @header_tabs ||= (nav_ready? && Current.tenant_id ? TabHistory.descriptors(session) : [])
  end

  def nav_ready? = ActiveRecord::Base.connection.schema_cache.data_source_exists?("products")

  # 사이드바 배지: 내가 지정 리뷰어인 pending 리뷰 수(RLS 테넌트 스코프). 요청당 1회 메모이즈.
  # reviewer_id로 필터 + 유니크 인덱스(tenant_id, approval_request_id, reviewer_id)라 요청당 조인 1행 →
  # .distinct 불요(정렬/해시 dedup 제거 = 매 인증 페이지 COUNT 비용 절감).
  def pending_review_count
    @pending_review_count ||= if nav_ready? && Current.tenant_id && current_user
      ApprovalRequest.where(status: "pending").joins(:approval_request_reviewers)
                     .where(approval_request_reviewers: { reviewer_id: current_user.id }).count
    else
      0
    end
  end

  # overdue 배지(warn 병기): pending_review_count와 동일 스코프(내가 지정 리뷰어인 pending = Segment A)에
  # `due_at < now`만 얹은 부분집합(overdue ≤ pending). 배지 정책(REF L493)은 pending 카운트를 불변으로 두고,
  # overdue는 별도 warn 배지로만 병기한다 — **개인 액션어블·bounded**하게 내 Segment A로 한정(Segment B는
  # 여전히 완전 미배지, 인박스 행 강조로만 노출). 요청당 1회 메모이즈(0도 캐시되게 defined? 가드).
  def overdue_review_count
    return @overdue_review_count if defined?(@overdue_review_count)

    @overdue_review_count = if nav_ready? && Current.tenant_id && current_user
      ApprovalRequest.where(status: "pending").where("due_at < ?", Time.current)
                     .joins(:approval_request_reviewers)
                     .where(approval_request_reviewers: { reviewer_id: current_user.id }).count
    else
      0
    end
  end

  # 대시보드 셸의 제품 트리 행 (대시보드 index / 상세 풀요청 공용). 표시 루트는 가시집합 기준(D3).
  # 가시 제품 전체를 프리로드와 함께 1회 로드 → tree_preorder가 parent_id 그룹핑으로 preorder를 만든다.
  # 하위 레벨의 children/연관(담당자·구성요소) 재쿼리 N+1이 제거되고(R5), 표시 루트 재루팅(부모 비가시)은
  # tree_preorder가 내포하므로 visible_roots를 거치지 않는다(:children 프리로드도 불요 — .children 미접근).
  # workspace(WS-track /workspaces/:id): 가시집합을 그 작업실의 모든 루트 서브트리로 좁혀 작업실 페이지 트리를
  # 만든다(가시성과 교집합이라 스코프 계정도 안전). 반환값 = 필터 전 가시 배열(작업실 가시성 판정용 — dashboard#index).
  def load_dashboard_rows(workspace: nil)
    visible = policy_scope(Product.includes(:parent, :owner, :workspace, { product_members: :user },
                                            { components: :component_versions })).to_a
    rows_source = visible
    if workspace
      keep = workspace_subtree_ids(workspace).to_set
      rows_source = visible.select { |p| keep.include?(p.id) }
    end
    @rows = Product.tree_preorder(rows_source)
    visible
  end

  # 작업실의 모든 루트 서브트리 id(멤버 요약·pending·회수 필터 공용). workspace.products = 그 작업실 루트들.
  def workspace_subtree_ids(workspace)
    Product.subtree_ids(workspace.products.pluck(:id))
  end

  # 작업실 페이지의 멤버 요약 = 그 작업실에 스코프 grant를 가진 계정(tenant-wide 제외 — 전역 멤버는 작업실
  # 소속이 아님). member_account_ids_for_workspace(작업실 grant + 서브트리 p/c grant)는 빈 작업실도 workspace grant
  # 멤버를 표면화한다(제품 파생 scoped_member_account_ids의 빈-집합 조기반환 우회 — D3).
  def workspace_member_accounts(workspace)
    ids = Authz::AdminScope.member_account_ids_for_workspace(workspace)
    Account.includes(:user, role_assignments: [ :scope_workspace, :scope_product, :scope_component ])
           .where(id: ids).order(:created_at)
  end
end
