require "application_system_test_case"

# 화면 캡처 + 핵심 인터랙션(뷰어 포커스) 검증
class ScreensTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  def hero
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
  end

  test "capture screens" do
    dir = Rails.root.join("tmp/screens")
    FileUtils.mkdir_p(dir)
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
    assert_text "스크리닝 결과"
    sleep 0.8
    save_screenshot(dir.join("3_screening.png"))

    # ③ 버전 비교 v4 — 듀얼 + 캔버스 밖 크롬
    visit comparison_path(from_id: v5.id, to_id: v6.id)
    assert_text "피드백"
    sleep 1.0 # 이미지 로드 + autofocus 박스#1 (힌트 토스트 보임)
    save_screenshot(dir.join("4_compare.png"))

    # 힌트 사라진 뒤 fit → 깨끗한 듀얼 전체 보기 (v5/v6 라벨·필름스트립)
    sleep 2.7
    find("button", text: "전체").click
    sleep 0.6
    save_screenshot(dir.join("4b_compare_fit.png"))

    # 썸네일 클릭 → 해당 피드백 포커스(양쪽 동시)
    find(".av-thumb[data-seq='3']").click
    sleep 0.8
    save_screenshot(dir.join("5_compare_focus.png"))
    assert_text "이전"

    # 반응형 + 가로 오버플로 0 검증 (1366·1280px)
    page.driver.browser.manage.window.resize_to(1366, 900)
    visit root_path
    assert_text "레티놀 3% 세럼"
    sleep 0.5
    save_screenshot(dir.join("6_dashboard_1366.png"))

    [1366, 1280].each do |w|
      page.driver.browser.manage.window.resize_to(w, 860)
      visit comparison_path(from_id: v5.id, to_id: v6.id)
      assert_text "피드백"
      sleep 0.9
      sw = page.evaluate_script("document.querySelector('main').scrollWidth")
      cw = page.evaluate_script("document.querySelector('main').clientWidth")
      assert sw <= cw + 1, "#{w}px: main 가로 오버플로 (scrollWidth #{sw} > clientWidth #{cw})"
      save_screenshot(dir.join("compare_#{w}.png"))
    end
  end
end
