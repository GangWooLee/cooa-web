require "test_helper"

class ComponentTest < ActiveSupport::TestCase
  test "display_name: name 우선 → type_label → 기본값" do
    assert_equal "박스 디자인", Component.new(name: "박스 디자인", component_type: "outer_box").display_name
    assert_equal "단상자", Component.new(component_type: "outer_box").display_name
    assert_equal "구성요소", Component.new.display_name
  end

  test "type_label nil-safe (component_type 없을 수 있음)" do
    assert_nil Component.new.type_label
    assert_equal "용기", Component.new(component_type: "container").type_label
  end
end
