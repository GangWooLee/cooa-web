require "application_system_test_case"

class SidebarToggleTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  def sidebar_right
    page.evaluate_script("(() => { const e=document.getElementById('app-sidebar'); return e ? Math.round(e.getBoundingClientRect().right) : -999 })()")
  end
  def collapsed? = page.evaluate_script("document.documentElement.classList.contains('sidebar-collapsed')")

  test "사이드바 닫기/열기 + 쿠키로 네비 후 유지" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    visit root_path
    assert_selector "#app-sidebar", wait: 6
    assert sidebar_right > 0, "초기엔 사이드바 보임"

    find("button[title='사이드바 닫기']").click
    sleep 0.5
    assert collapsed?, "collapsed 클래스 적용"
    assert sidebar_right <= 0, "닫힘 시 사이드바 화면 밖(완전 비가시)"
    assert_selector "#sidebar-open", visible: true, wait: 6

    find("#sidebar-open").click
    sleep 0.5
    refute collapsed?, "다시 펼침"
    assert sidebar_right > 0, "사이드바 복귀"

    find("button[title='사이드바 닫기']").click
    sleep 0.4
    visit product_path(Product.find_by(code: "CO0001"))
    assert collapsed?, "네비 후에도 닫힘 유지(쿠키 서버 렌더)"
    assert sidebar_right <= 0
  end
end
