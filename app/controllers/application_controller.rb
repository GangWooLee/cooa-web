class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_tenant
  around_action :scope_to_tenant
  before_action :set_current_user
  before_action :set_nav
  helper_method :current_user, :header_tabs

  private

  # 데모: 고정 사용자 자동 로그인 (인증 생략)
  def set_current_user
    Current.user = User.find_by(name: "김쿠아") || User.first
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

    @tree_roots = Product.roots.includes(:children)
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
    @rows = Product.tree_preorder(Product.roots.includes(:children, :owner, { product_members: :user },
                                                          { components: :component_versions }))
  end
end
