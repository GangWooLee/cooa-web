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
    # 상단바 정합: 첫 히스토리 탭 우측 ≈ 사이드바 우측 (격자 일치)
    assert_selector "header nav a", minimum: 1
    tab_r  = page.evaluate_script("document.querySelector('header nav a').getBoundingClientRect().right")
    side_r = page.evaluate_script("document.querySelector('aside').getBoundingClientRect().right")
    assert_in_delta tab_r, side_r, 2, "첫 탭 우측(#{tab_r})이 사이드바 우측(#{side_r})과 정합해야 함"
    sleep 0.4
    save_screenshot(dir.join("1_dashboard.png"))

    # ── 마스터-디테일: 리프 행(셀) 클릭 → 우측 드로어 상세 ──
    within("table") { find("td", text: "CO0001").click }
    sleep 0.7
    assert_selector "[data-detail-drawer-target='panel']"
    assert_text "구성요소" # 드로어에 상세 로드
    save_screenshot(dir.join("1b_dashboard_detail.png"))
    # 닫기 → 드로어 닫힘 + URL 정리(/)
    find("button[aria-label='닫기']").click
    sleep 0.4
    assert_equal "/", URI.parse(current_url).path, "닫기 후 URL은 대시보드(/)"

    # ── 폴더 클릭 = 트리 토글(별도 페이지 이동 없음) ──
    within("table") { find("td", text: "레티놀 3% 세럼").click }
    sleep 0.3
    assert_equal "/", URI.parse(current_url).path, "폴더 클릭은 페이지 이동 없어야 함"

    visit product_path(Product.find_by(code: "CO0001"))
    assert_text "구성요소"
    assert_no_selector "a[href*='/compare/']" # 변경사유 콜아웃 기본 접힘
    # 슬롯 액션바: 같은 구성요소 두 버전 선택 → [비교 열기] 활성
    nodes = all("button[data-version-select-target='version']")
    nodes[0].click
    nodes[1].click
    sleep 0.3
    assert_selector "button[data-version-select-target='compareBtn']:not([disabled])"
    save_screenshot(dir.join("2_product.png"))
    # 다른 구성요소 버전 선택 → 비교쌍 리셋(데드엔드 방지)
    nodes[6].click # 용기 v1 (다른 구성요소)
    sleep 0.2
    assert_selector "button[data-version-select-target='compareBtn'][disabled]"
    nodes[7].click # 용기 v2 (같은 구성요소) → 다시 활성
    sleep 0.2
    assert_selector "button[data-version-select-target='compareBtn']:not([disabled])"
    # ▾ 변경사유 펼침 → 콜아웃 비교 링크
    first("button[data-version-timeline-target='dot']").click
    sleep 0.3
    assert_selector "a[href*='/compare/']", minimum: 1
    save_screenshot(dir.join("2b_product_reason.png"))

    visit screening_component_version_path(v5)
    assert_text "스크리닝 결과"
    assert_no_selector "button", text: "전체" # 스크리닝도 줌 버튼 제거(일관성)
    sleep 0.8
    save_screenshot(dir.join("3_screening.png"))

    # ③ 버전 비교 — 듀얼 + 상단 정리(줌 버튼 제거·라벨 좌상단)
    visit comparison_path(from_id: v5.id, to_id: v6.id)
    assert_text "피드백"
    assert_no_selector "button", text: "전체" # 비교엔 줌 버튼 없음
    sleep 1.0 # 이미지 로드 + autofocus 박스#1
    save_screenshot(dir.join("4_compare.png"))

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
