require "application_system_test_case"

class SidebarToggleTest < ApplicationSystemTestCase
  def sidebar_right
    page.evaluate_script("(() => { const e=document.getElementById('app-sidebar'); return e ? Math.round(e.getBoundingClientRect().right) : -999 })()")
  end
  def sidebar_box = page.evaluate_script("(() => { const r=document.getElementById('app-sidebar').getBoundingClientRect(); return { left: Math.round(r.left), right: Math.round(r.right) } })()")
  def backdrop_box = page.evaluate_script("(() => { const r=document.getElementById('sidebar-backdrop').getBoundingClientRect(); return { left: Math.round(r.left), right: Math.round(r.right) } })()")
  def collapsed? = page.evaluate_script("document.documentElement.classList.contains('sidebar-collapsed')")

  TOGGLE = "header [data-sidebar-target='toggle']".freeze

  test "상단바 토글로 사이드바 닫기/열기 + 쿠키로 네비 후 유지" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_selector "#app-sidebar", wait: 6
    assert_selector TOGGLE, visible: true # 토글은 상단바에 항상 노출
    assert sidebar_right > 0, "초기엔 사이드바 보임"

    find(TOGGLE).click
    sleep 0.5
    assert collapsed?, "collapsed 클래스 적용"
    assert sidebar_right <= 0, "닫힘 시 사이드바 화면 밖(완전 비가시)"
    assert_selector TOGGLE, visible: true # 토글은 닫힘 후에도 같은 자리

    find(TOGGLE).click
    sleep 0.5
    refute collapsed?, "다시 펼침"
    assert sidebar_right > 0, "사이드바 복귀"

    find(TOGGLE).click
    sleep 0.4
    visit product_path(Product.find_by(code: "CO0001"))
    assert collapsed?, "네비 후에도 닫힘 유지(쿠키 서버 렌더)"
    assert sidebar_right <= 0
  end

  test "모바일 토글은 사이드바를 오프캔버스로 열고 backdrop으로 닫는다" do
    page.current_window.resize_to(390, 844)
    visit root_path
    assert_selector "#app-sidebar", wait: 6
    assert_selector TOGGLE, visible: true

    assert sidebar_box["right"] <= 0, "모바일 초기 사이드바는 화면 밖"
    assert_equal "false", find(TOGGLE)["aria-expanded"]

    find(TOGGLE).click
    sleep 0.35
    assert_equal 0, sidebar_box["left"], "열림 시 사이드바 좌측이 viewport에 맞아야 함"
    assert_equal "true", find(TOGGLE)["aria-expanded"]
    assert_selector "#sidebar-backdrop", visible: true
    assert_equal 281, backdrop_box["left"], "backdrop은 사이드바 오른쪽 영역만 덮어야 함"

    find("#sidebar-backdrop").click
    sleep 0.35
    assert sidebar_box["right"] <= 0, "backdrop 클릭 후 사이드바는 다시 화면 밖"
    assert_equal "false", find(TOGGLE)["aria-expanded"]
  end
end
