require "application_system_test_case"

# 4개 화면을 헤드리스 브라우저로 캡처 (tmp/screens/*.png)
class ScreensTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  test "capture 4 screens" do
    dir = Rails.root.join("tmp/screens")
    FileUtils.mkdir_p(dir)

    hero = Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
    v5 = hero.component_versions.find_by(version_number: 5)
    v6 = hero.component_versions.find_by(version_number: 6)

    visit root_path
    assert_text "레티놀 3% 세럼"
    sleep 0.4
    save_screenshot(dir.join("1_dashboard.png"))

    visit product_path(Product.find_by(code: "CO0001"))
    assert_text "구성요소"
    sleep 0.3
    save_screenshot(dir.join("2_product.png"))

    visit screening_component_version_path(v5)
    assert_text "인허가 스크리닝 결과"
    sleep 0.4
    save_screenshot(dir.join("3_screening.png"))

    visit comparison_path(from_id: v5.id, to_id: v6.id)
    assert_text "피드백 아카이빙"
    sleep 0.4
    save_screenshot(dir.join("4_compare.png"))
  end
end
