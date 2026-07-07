class ProductsController < ApplicationController
  include Positionable

  # 파괴는 감사(allow)를 남기므로 도메인 액터 가드 선행(E4) — 미브리지 계정은 AuditLog.record!의 fail-closed
  # raise(500)에 닿기 전 403으로 막는다(workspaces#destroy와 동일 규약). 다른 액션은 감사 미기록이라 대상 아님.
  before_action :require_domain_actor, only: :destroy

  # ② 데이터 매핑 = 제품 클릭 상세보기 (허브) — 트리 노드
  def show
    # pm.user·어노테이션 created_by는 상세/구성요소 뷰에서 표시 리졸버(account-우선)를 타므로 :account까지 프리로드(R5).
    @product = Product.includes(:owner, :parent, :children, product_members: { user: :account },
                                components: { component_versions: [ :ingredients, { annotations: [ { created_by: :account }, :comments ] } ] }).find(params[:id])
    authorize @product, :view_product?
    # 폴더는 드로어 대상 아님 — 풀요청이면 대시보드(해당 폴더 펼침)로(브레드크럼/직접 URL 방어)
    return redirect_to root_path(focus: @product.id) if @product.folder? && !turbo_frame_request?
    @ancestors = @product.self_and_ancestors
    # 드로어(제품) 진입은 히스토리에 기록하지 않음 — 풀페이지 작업(버전/비교/스크리닝)만 기록
    # 풀요청이면 셸의 트리 리스트도 렌더하되 **그 리프의 작업실로 스코프**한다(F1). 스코프를 빼면 @rows가
    # 가시 전체가 돼 사이드바(그 작업실)와 본문(전 작업실)이 분열한다 — dashboard#index의 focus 경로와 동일한
    # 본문 스코프를 리프 상세 풀요청에도 부여(같은 load_dashboard_rows workspace: 계약).
    unless turbo_frame_request?
      ws = workspace_of_node(@product)
      # fail-closed: 작업실 미도출이면 홈으로 — 현재는 도달 불가(뷰 인가 ⟺ 가시 서브트리 소속이라 항상
      # 도출됨)지만, 인가/가시성 규칙이 분기하는 미래에 무필터 전체 렌더(F1 재발)로 퇴행하지 않게 잠근다.
      return redirect_to root_path if ws.nil?

      load_dashboard_rows(workspace: ws)
    end
  end

  # 즉시 생성(폼 없음) — 선택 노드 기준 위치에 만들고 트리에서 인라인 명명(드로어 안 띄움)
  def create
    @product = Product.new(product_params)
    apply_creation_context(@product) # parent_id(선택 기준) + position(형제 맨 아래)
    assign_creation_workspace(@product) # 루트면 작업실 귀속(현재 작업실 주입 · 없으면 모델이 새 작업실 생성)
    @product.name = default_name(@product) if @product.name.blank?
    authorize @product, :manage_product?
    authorize @product, :manage_members? if params[:members].present?
    if @product.save
      sync_members(@product) if @product.leaf? # 항목 생성 시 담당자(있으면)
      redirect_to creation_redirect(@product)
    else
      redirect_back fallback_location: root_path,
                    alert: @product.errors.full_messages.to_sentence.presence || "항목을 만들지 못했습니다."
    end
  end

  # 모든 편집은 인라인(별도 편집 페이지 없음). 실패 시 되돌림.
  # return=tree(트리 인라인 rename)는 트리로, 그 외(드로어 편집)는 드로어로.
  def update
    @product = Product.find(params[:id])
    authorize @product, :manage_product?
    authorize @product, :manage_members? if params[:members].present?
    if @product.update(product_params)
      sync_members(@product) if @product.leaf?
      # 트리 인라인 rename → 그 노드의 작업실로 복귀(focus로 조상 펼침·노드 가시). 그 외 → 드로어.
      redirect_to(params[:return] == "tree" ? root_path(focus: @product.id) : product_path(@product))
    else
      redirect_back fallback_location: product_path(@product),
                    alert: @product.errors.full_messages.to_sentence.presence || "변경 사항을 저장하지 못했습니다."
    end
  end

  def destroy
    product = Product.find(params[:id])
    authorize product, :manage_product?
    workspace = workspace_of_node(product) # 삭제 전 작업실(Workspace 엔티티) 포착
    summary = destruction_summary(product) # 삭제 전 하위 개수(연쇄 삭제 대상) 수집 — 파괴 후엔 셀 수 없음
    product.destroy # children·components·versions·annotations 연쇄 삭제
    audit_destroy!(product, summary)
    # 작업실에 아직 (다른) 루트가 남아 있으면 그 작업실 트리로 복귀, 마지막 루트를 지웠으면 홈(작업실 카드)으로.
    redirect_to(workspace&.products&.exists? ? workspace_path(workspace) : root_path)
  end

  # 드래그앤드롭 트리 이동 — parent_id(빈값=루트) + before_id/after_id(형제 기준).
  # 자기·자손·비폴더 부모는 모델 검증(parent_not_self_or_descendant)이 거부 → 422(500 아님).
  def move
    node = Product.find(params[:id])
    authorize node, :manage_product?
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

  # 생성 직후 리다이렉트(origin별):
  #  · side  → 사이드바 컨텍스트 트리에서 인라인 명명(rename_side). root_path의 rename_side 파라미터가 그 노드의
  #            작업실을 컨텍스트로 잡아 사이드바 트리를 렌더한다(무회귀).
  #  · 그 외 → 작업실 트리 테이블에서 인라인 명명(rename).
  # 홈 "새 작업실"은 products#create가 아니라 workspaces#create로 은퇴(D3) — origin=workspace 분기 제거.
  def creation_redirect(product)
    params[:origin] == "side" ? root_path(rename_side: product.id) : root_path(rename: product.id)
  end

  # 루트 생성 시 작업실 귀속: 명시 workspace_id(사이드바 "새 폴더" = 현재 작업실)면 그 작업실에 넣고, 없으면
  # 모델의 heal 콜백이 동명 새 작업실을 만든다(홈 "새 작업실"). 자식 생성은 workspace_id를 무시(brand_root로 도출).
  def assign_creation_workspace(product)
    return if product.parent_id.present?
    return unless (wid = params[:workspace_id].presence)

    product.workspace = Workspace.find_by(id: wid) # RLS 동일테넌트만 조회 · nil이면 heal이 새 작업실 생성(안전 폴백)
  end

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
    product.position = next_position(Product.where(parent_id: product.parent_id))
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
    permitted = %i[name code country channel deadline]
    # kind·parent_id는 생성 시에만 — update로 재부모화 차단(이동은 move/DnD가 position까지 재작성)
    permitted += %i[kind parent_id] if action_name == "create"
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

  # 파괴 전 하위 개수 요약(감사 after). destroy가 subtree(자기+자손) 제품과 그 구성요소·버전을 연쇄 삭제하므로
  # "무엇이 함께 사라졌는지"를 남긴다 — subtree_ids로 자손 제품 수를, 그 제품들의 구성요소·버전을 집계.
  def destruction_summary(product)
    subtree = Product.subtree_ids(product.id)
    component_ids = Component.where(product_id: subtree).pluck(:id)
    versions = component_ids.empty? ? 0 : ComponentVersion.where(component_id: component_ids).count
    { name: product.name, descendants: subtree.size - 1, components: component_ids.size, versions: versions }
  end

  # 파괴 감사(allow) — workspaces#audit_workspace! 패턴. resource_id = 파괴된 제품 id(객체는 destroy 후에도 id 보유).
  def audit_destroy!(product, summary)
    AuditLog.record!(action: "product.destroy", resource_type: "Product", resource_id: product.id, outcome: "allow",
                     after: summary, request_id: request.request_id, source_ip: request.remote_ip,
                     user_agent: request.user_agent)
  end
end
