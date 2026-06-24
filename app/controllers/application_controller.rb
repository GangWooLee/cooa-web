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

  # 모든 화면 공통 셸 데이터 (사이드바 브랜드, 상단 열린 품목 탭 = 세션 히스토리)
  def set_nav
    return unless ActiveRecord::Base.connection.schema_cache.data_source_exists?("products")

    @tree_roots = Product.roots.includes(:children)
    ids = session[:open_tabs] || []
    by_id = Product.where(id: ids).includes(:components).index_by(&:id)
    @open_tabs = ids.filter_map { |id| by_id[id] } # 순서 보존 + 삭제된 항목 제외
  end

  # 대시보드 셸의 제품 트리 행 (대시보드 index / 상세 풀요청 공용)
  def load_dashboard_rows
    @rows = Product.tree_preorder(Product.roots.includes(:children, :owner, { product_members: :user },
                                                          { components: :component_versions }))
  end
end
