class ProductsController < ApplicationController
  # ② 데이터 매핑 = 제품 클릭 상세보기 (허브) — 트리 노드
  def show
    @product = Product.includes(:owner, :parent, :children, product_members: :user,
                                components: { component_versions: [:ingredients, { annotations: [:created_by, :comments] }] }).find(params[:id])
    @ancestors = @product.self_and_ancestors
    track_open_tab(@product) # 헤더 히스토리 탭에 추가
    load_dashboard_rows unless turbo_frame_request? # 풀요청이면 셸의 트리 리스트도 렌더
  end

  # 즉시 생성(폼 없음) — 선택 노드 기준 위치에 만들고 트리에서 인라인 명명(드로어 안 띄움)
  def create
    @product = Product.new(product_params)
    apply_creation_context(@product) # parent_id(선택 기준) + position(형제 맨 아래)
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

  # 드래그앤드롭 트리 이동 — parent_id(빈값=루트) + before_id/after_id(형제 기준).
  # 자기·자손·비폴더 부모는 모델 검증(parent_not_self_or_descendant)이 거부 → 422(500 아님).
  def move
    node = Product.find(params[:id])
    node.parent_id = params[:parent_id].presence
    return head :unprocessable_entity unless node.valid?

    Product.transaction do
      node.save!
      siblings = Product.where(parent_id: node.parent_id).order(:position, :id).to_a
      siblings.delete(node)
      idx = sibling_index(siblings)
      siblings.insert(idx, node)
      siblings.each_with_index { |s, i| Product.where(id: s.id).update_all(position: i) }
    end
    head :ok
  rescue ActiveRecord::RecordInvalid
    head :unprocessable_entity
  end

  private

  # before_id면 그 앞, after_id면 그 뒤, 둘 다 없으면 맨 끝(=폴더 안으로 떨굼 append)
  def sibling_index(siblings)
    if (bid = params[:before_id].presence)
      i = siblings.index { |s| s.id.to_s == bid.to_s }
      i || siblings.size
    elsif (aid = params[:after_id].presence)
      i = siblings.index { |s| s.id.to_s == aid.to_s }
      i ? i + 1 : siblings.size
    else
      siblings.size
    end
  end

  # 생성 위치 규칙(단일 출처): relative_to(선택 노드) 기준. 명시적 parent_id가 오면 존중.
  #  - 없음 → 루트 / 선택 폴더 → 그 폴더 자식 / 선택 리프 → 그 형제. position은 항상 맨 아래.
  def apply_creation_context(product)
    if product.parent_id.blank? # 명시적 parent_id(사이드바/레거시)는 존중
      rel = Product.find_by(id: params[:relative_to])
      product.parent_id = rel&.folder? ? rel.id : rel&.parent_id
    end
    product.position = next_position(product.parent_id)
  end

  def next_position(parent_id)
    (Product.where(parent_id: parent_id).maximum(:position) || -1) + 1
  end

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
