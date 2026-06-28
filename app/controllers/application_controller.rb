class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include Pundit::Authorization
  # Auth (ADR-003): resolve_account → set_current_tenant → scope_to_tenant(RLS tx) → verify_revocation.
  include Authentication

  before_action :set_nav
  helper_method :header_tabs

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
    if request.get? && request.format.html?
      redirect_to root_path, alert: "권한이 없습니다.", status: :see_other
    else
      head :forbidden
    end
  end

  # 모든 화면 공통 셸 데이터 (사이드바 트리). 히스토리 탭은 header_tabs(렌더 시점)로 분리.
  def set_nav
    return unless nav_ready? && Current.tenant_id

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
