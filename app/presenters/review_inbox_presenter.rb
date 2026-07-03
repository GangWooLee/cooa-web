# 리뷰 인박스 Segment B(리뷰어 미배정 — 내가 맡을 수 있는 리뷰)의 계산: 브랜드(루트 제품) 그룹핑 + 필터.
# 조상(브랜드 루트) 계산은 반드시 in-memory 맵으로 — product.self_and_ancestors는 .parent walk라 목록
# 렌더에서 N+1을 낸다. products(policy_scope(Product.all))를 id로 색인해 parent_id를 메모리에서 따라간다.
class ReviewInboxPresenter
  Group = Struct.new(:brand, :requests)

  def initialize(unassigned:, products:, brand_filter: nil)
    @unassigned = unassigned.to_a
    @by_id = products.to_a.index_by(&:id)
    @filter = normalize_filter(brand_filter)
  end

  def any? = filtered.any?

  # [Group(brand, requests), …] — 브랜드명(동명은 id) 오름차순.
  def groups
    filtered.group_by { |r| brand_root(r.component_version.component.product) }
            .sort_by { |b, _| [ b.name, b.id ] }
            .map { |b, rs| Group.new(b, rs) }
  end

  # 필터 링크 후보(브랜드 루트, 중복 제거·이름순). 필터 적용 전 전체 집합 기준.
  def brand_options
    @unassigned.map { |r| brand_root(r.component_version.component.product) }.uniq(&:id).sort_by(&:name)
  end

  def active_filter = @filter

  private

  def filtered
    return @unassigned if @filter.nil?

    @unassigned.select { |r| brand_root(r.component_version.component.product).id == @filter }
  end

  # 리프 제품에서 parent_id를 in-memory 맵으로 따라 올라가 브랜드 루트를 찾는다(쿼리 0건).
  def brand_root(product)
    node = @by_id[product.id] || product
    node = @by_id[node.parent_id] while node.parent_id && @by_id[node.parent_id]
    node
  end

  # 신뢰 못 할 파라미터 방어: 실제 브랜드 옵션 id에 있을 때만 필터 적용(그 외엔 무필터).
  def normalize_filter(v)
    id = v.presence&.to_i
    return nil if id.nil? || id.zero?

    brand_options.map(&:id).include?(id) ? id : nil
  end
end
