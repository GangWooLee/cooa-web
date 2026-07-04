class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pundit::Authorization
  # Auth (ADR-003): resolve_account → set_current_tenant → scope_to_tenant(RLS tx) → verify_revocation.
  include Authentication

  before_action :set_nav
  helper_method :header_tabs, :pending_review_count, :visible_product_id_set

  # Strict Pundit (ADR-002 §0 BOLA defense): every action must authorize (or explicitly skip_authorization).
  # verify_policy_scoped is enabled per-controller for index-like actions (DashboardController) — referencing
  # :index here would raise on controllers without an :index action (raise_on_missing_callback_actions).
  after_action :verify_authorized
  rescue_from Pundit::NotAuthorizedError, with: :deny_access

  private

  # Pundit "user" = role-resolution context: the authenticated Account (roles via AssignmentResolver).
  def pundit_user = Authz::AccessContext.new(actor: Current.account)

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

  # 모든 화면 공통 셸 데이터 (사이드바 트리). 히스토리 탭은 header_tabs(렌더 시점)로 분리.
  def set_nav
    return unless nav_ready? && Current.tenant_id

    @tree_roots = visible_roots(Product.includes(:children, :parent))
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

  # 대시보드 셸의 제품 트리 행 (대시보드 index / 상세 풀요청 공용). 표시 루트는 가시집합 기준(D3).
  def load_dashboard_rows
    roots = visible_roots(Product.includes(:children, :parent, :owner, { product_members: :user },
                                           { components: :component_versions }))
    @rows = Product.tree_preorder(roots)
  end
end
