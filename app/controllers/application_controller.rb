class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_current_user
  before_action :set_nav
  helper_method :current_user

  private

  # 데모: 고정 사용자 자동 로그인 (인증 생략)
  def set_current_user
    Current.user = User.find_by(name: "김쿠아") || User.first
  end

  def current_user = Current.user

  # 모든 화면 공통 셸 데이터 (사이드바 트리, 상단 히스토리 탭)
  def set_nav
    return unless ActiveRecord::Base.connection.schema_cache.data_source_exists?("products")

    @tree_roots = Product.roots.includes(:children)
    @open_tabs = (session[:open_tabs] || []).filter_map { |key| tab_descriptor(key) } # 순서 보존 + 삭제된 대상 제외
  end

  # 히스토리 탭(세션) — 제품(p)/버전보기(v)/스크리닝(s)을 한 목록으로. 중복제거·최신순·최대 8개.
  def track_tab(type, id)
    key = "#{type}-#{id}"
    tabs = (session[:open_tabs] || []).reject { |k| k == key }
    tabs.unshift(key)
    session[:open_tabs] = tabs.first(8)
  end

  # 키("p-1"/"v-5"/"s-5") → 탑바 렌더용 디스크립터(삭제된 대상이면 nil)
  def tab_descriptor(key)
    type, id = key.split("-", 2)
    case type
    when "p"
      p = Product.where(id: id).includes(:components).first
      p && { key: key, type: "p", code: p.code, path: product_path(p), frame: "detail", product: p }
    when "v", "s"
      v = ComponentVersion.where(id: id).includes(component: :product).first
      next_path = type == "v" ? component_version_path(v) : screening_component_version_path(v) if v
      v && { key: key, type: type, code: v.product.code, path: next_path, frame: nil, version: v }
    end
  end

  # 대시보드 셸의 제품 트리 행 (대시보드 index / 상세 풀요청 공용)
  def load_dashboard_rows
    @rows = Product.tree_preorder(Product.roots.includes(:children, :owner, { product_members: :user },
                                                          { components: :component_versions }))
  end
end
