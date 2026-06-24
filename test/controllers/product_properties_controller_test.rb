require "test_helper"

class ProductPropertiesControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def leaf = Product.find_by(code: "CO0001")

  test "속성 즉시 추가 → rename_property 리다이렉트 + 기본 키명" do
    l = leaf
    assert_difference -> { l.product_properties.count }, 1 do
      post product_product_properties_path(l)
    end
    prop = l.product_properties.order(:id).last
    assert_equal "속성", prop.name
    assert_equal l.product_properties.maximum(:position), prop.position
    assert_redirected_to product_path(l, rename_property: prop.id)
  end

  test "키 이름변경(빈 키 무시)" do
    l = leaf
    prop = l.product_properties.create!(name: "속성", position: 0)
    patch product_product_property_path(l, prop), params: { product_property: { name: "  용량  " } }
    assert_equal "용량", prop.reload.name # strip + 정상 변경
    patch product_product_property_path(l, prop), params: { product_property: { name: "   " } }
    assert_equal "용량", prop.reload.name, "빈 키는 무시(키 사라짐 방지)"
  end

  test "값 편집(빈 값 허용 → None 표시)" do
    l = leaf
    prop = l.product_properties.create!(name: "용량", position: 0)
    patch product_product_property_path(l, prop), params: { product_property: { value: "30ml" } }
    assert_equal "30ml", prop.reload.value
    patch product_product_property_path(l, prop), params: { product_property: { value: "" } }
    assert_equal "", prop.reload.value.to_s, "값은 비울 수 있음"
  end

  test "속성 삭제" do
    l = leaf
    prop = l.product_properties.create!(name: "용량", position: 0)
    assert_difference -> { ProductProperty.count }, -1 do
      delete product_product_property_path(l, prop)
    end
    assert_redirected_to product_path(l)
  end
end
