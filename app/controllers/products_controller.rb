class ProductsController < ApplicationController
  # ② 데이터 매핑 = 제품 클릭 상세보기 (허브) — 트리 노드
  def show
    @product = Product.includes(:owner, :parent, :children, product_members: :user,
                                components: { component_versions: [:ingredients, { annotations: [:created_by, :comments] }] }).find(params[:id])
    @ancestors = @product.self_and_ancestors
    track_open_tab(@product) # 헤더 히스토리 탭에 추가
    load_dashboard_rows unless turbo_frame_request? # 풀요청이면 셸의 트리 리스트도 렌더
  end

  # 즉시 생성(폼 없음) — 기본 이름으로 만들고 트리에서 인라인 명명(드로어 안 띄움)
  def create
    @product = Product.new(product_params)
    @product.name = default_name(@product) if @product.name.blank?
    if @product.save
      sync_members(@product) if @product.leaf? # 항목 생성 시 담당자(있으면)
      redirect_to root_path(rename: @product.id)
    else
      redirect_back fallback_location: root_path
    end
  end

  # 모든 편집은 인라인(별도 편집 페이지 없음). 실패 시 되돌림.
  # return=tree(트리 인라인 rename)는 트리로, 그 외(드로어 편집)는 드로어로.
  def update
    @product = Product.find(params[:id])
    if @product.update(product_params)
      sync_members(@product) if @product.leaf?
      redirect_to(params[:return] == "tree" ? root_path : product_path(@product))
    else
      redirect_back fallback_location: product_path(@product)
    end
  end

  def destroy
    product = Product.find(params[:id])
    product.destroy # children·components·versions·annotations 연쇄 삭제
    redirect_to root_path
  end

  private

  # 헤더 히스토리 탭(세션) — 최근 연 코드 보유 제품, 중복제거, 최대 8개
  def track_open_tab(product)
    return if product.code.blank?
    tabs = session[:open_tabs] || []
    tabs.delete(product.id)
    tabs.unshift(product.id)
    session[:open_tabs] = tabs.first(8)
  end

  # 즉시 생성 기본 이름(생성 직후 인라인으로 변경)
  def default_name(product)
    product.folder? ? "제목 없음 폴더" : "제목 없음"
  end

  # kind는 생성 시에만 허용(수정에서 폴더↔항목 전환 금지 — 구성요소/하위 고아 방지)
  # owner_id 제거 — 소유자는 담당자(role "소유자")로 통합.
  # 담당자만 갱신하는 PATCH는 product 키가 없으므로 require 대신 빈 해시 허용.
  def product_params
    return {} unless params.key?(:product)
    permitted = %i[name code country channel deadline parent_id]
    permitted << :kind if action_name == "create"
    params.require(:product).permit(*permitted)
  end

  # 담당자: params[:members] = [{role, user_id}, …] → 전체 재구성(존재하는 user만, 트랜잭션).
  # 역할명은 자유 문자열(빈 역할 → "담당자"), 사람 미선택 행은 skip. members 미전송이면 보존.
  def sync_members(product)
    rows = params[:members]
    return if rows.nil?
    list = rows.respond_to?(:values) ? rows.values : rows # 배열 또는 인덱스해시 모두 허용
    pairs = Array(list).filter_map do |row|
      next unless row.respond_to?(:dig)
      uid  = row[:user_id].presence
      user = User.find_by(id: uid) if uid
      role = row[:role].to_s.strip
      { role: role.presence || "담당자", user_id: user.id } if user
    end
    Product.transaction do
      product.product_members.destroy_all
      pairs.each { |attrs| product.product_members.create!(attrs) }
    end
  end
end
