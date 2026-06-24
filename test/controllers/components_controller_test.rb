require "test_helper"

class ComponentsControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def item = Product.find_by(code: "CO0001")

  test "구성요소 즉시 추가(자유 이름) → rename_component 리다이렉트" do
    i = item
    assert_difference -> { i.components.count }, 1 do
      post product_components_path(i)
    end
    c = i.components.order(:id).last
    assert_equal "제목 없음 구성요소", c.name
    assert_equal i.components.maximum(:position), c.position
    assert_redirected_to product_path(i, rename_component: c.id)
  end

  test "구성요소 이름변경(인라인 PATCH)" do
    c = item.components.first
    patch component_path(c), params: { component: { name: "  바코드 라벨  " } }
    assert_equal "바코드 라벨", c.reload.name # strip
    assert_redirected_to product_path(item)
  end

  test "빈 이름 PATCH 무시" do
    c = item.components.first
    before = c.name
    patch component_path(c), params: { component: { name: "  " } }
    assert_equal before, c.reload.name
  end

  test "드래그 순서변경" do
    i = item
    ids = i.components.order(:position).pluck(:id)
    shuffled = ids.reverse
    patch reorder_product_components_path(i), params: { ids: shuffled }, as: :json
    assert_response :success
    assert_equal shuffled, i.components.order(:position).pluck(:id)
    # 다른 제품 구성요소는 영향 없음
    other = Product.find_by(code: "CO0000").components.order(:position).pluck(:id)
    patch reorder_product_components_path(i), params: { ids: other }, as: :json
    assert_equal shuffled, i.components.reload.order(:position).pluck(:id), "타 제품 id는 무시"
  end

  test "구성요소 삭제 → 버전 연쇄 제거" do
    c = item.components.find_by(component_type: "outer_box")
    ver_ids = c.component_versions.pluck(:id)
    assert ver_ids.any?
    delete component_path(c)
    assert_empty Component.where(id: c.id)
    assert_empty ComponentVersion.where(id: ver_ids)
  end
end
