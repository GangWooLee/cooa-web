class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pundit::Authorization

  before_action :set_current_tenant
  around_action :scope_to_tenant
  before_action :set_current_user
  before_action :set_nav
  helper_method :current_user, :header_tabs

  # Strict Pundit (ADR-002 §0 BOLA defense): every action must authorize (or explicitly skip_authorization).
  # verify_policy_scoped is enabled per-controller for index-like actions (DashboardController) — referencing
  # :index here would raise on controllers without an :index action (raise_on_missing_callback_actions).
  after_action :verify_authorized
  rescue_from Pundit::NotAuthorizedError, with: :deny_access

  private

  # Pundit "user" = role-resolution context. Phase 1 wraps Current.user; Phase 2 = Current.account (one line).
  def pundit_user = Authz::AccessContext.new(actor: Current.user)

  # deny → 403 for mutations/non-html (anti-enumeration; RLS already 404s other tenants' rows),
  # redirect+alert for GET html. Persistent audit_log row = Phase 3 (Phase 1 = structured log).
  def deny_access(exception)
    Rails.logger.warn("[authz][deny] verb=#{exception.query} record=#{exception.record.class} user=#{Current.user&.id} tenant=#{Current.tenant_id}")
    if request.get? && request.format.html?
      redirect_to root_path, alert: "권한이 없습니다.", status: :see_other
    else
      head :forbidden
    end
  end

  # 데모: 고정 사용자 자동 로그인 (인증 생략).
  # [dev/test seam] params[:_as]=user_id로 현재 사용자 전환(세션 지속) — SoD 양성경로 시연·테스트용.
  # production에선 무시. Phase 2에서 실인증(OIDC)으로 전면 교체.
  def set_current_user
    session[:current_user_id] = params[:_as] if params[:_as].present? && !Rails.env.production?
    Current.user = User.find_by(id: session[:current_user_id]) || User.find_by(name: "김쿠아") || User.first
  end

  def current_user = Current.user

  # Phase 0b: server-resolved tenant. Single demo tenant via session/seed; Phase 2 resolves it from the
  # authenticated Account. NEVER trust a client-supplied tenant (ADR-002 §7 / ADR-003 §2.1).
  def set_current_tenant
    Current.tenant_id = (session[:tenant_id] ||= Organization.first!.id)
  end

  # Wrap the whole request (action + view render) in the tenant's RLS context so every query —
  # incl. set_nav and views — runs scoped. SET LOCAL clears at transaction end (no pool leakage).
  def scope_to_tenant(&block)
    TenantContext.with_tenant(Current.tenant_id, &block)
  end

  # 모든 화면 공통 셸 데이터 (사이드바 트리). 히스토리 탭은 header_tabs(렌더 시점)로 분리.
  def set_nav
    return unless nav_ready?

    @tree_roots = policy_scope(Product.roots.includes(:children))
  end

  # 상단 히스토리 탭 — 렌더 시점에 계산해야 함. set_nav(before_action)는 액션의 TabHistory.track보다
  # 먼저 실행되므로 거기서 계산하면 "들어간 페이지"의 탭이 한 스텝 늦게 보임. 렌더 시점엔 track 이후라
  # 현재 항목이 포함됨(들어간 즉시 표시). lazy 메모이즈로 요청당 1회.
  def header_tabs
    @header_tabs ||= (nav_ready? ? TabHistory.descriptors(session) : [])
  end

  def nav_ready? = ActiveRecord::Base.connection.schema_cache.data_source_exists?("products")

  # 대시보드 셸의 제품 트리 행 (대시보드 index / 상세 풀요청 공용)
  def load_dashboard_rows
    @rows = Product.tree_preorder(policy_scope(Product.roots.includes(:children, :owner, { product_members: :user },
                                                                       { components: :component_versions })))
  end
end
