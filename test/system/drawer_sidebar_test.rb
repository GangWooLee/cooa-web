require "application_system_test_case"

class DrawerSidebarTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  # 같은 구성요소 행의 삭제버튼(absolute form) top 좌표
  def delete_top
    page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector("button[data-action*='version-timeline#toggle']");
        if (!t) return -1;
        const row = t.closest("[class*='group/comp']");
        const del = row && row.querySelector("form.absolute");
        return del ? Math.round(del.getBoundingClientRect().top) : -1;
      })()
    JS
  end

  test "Fix3+Fix1: 변경사유 토글을 열어도 삭제버튼 위치 고정 + 비교 열기 작동" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    hero = Product.find_by(code: "CO0001")
    visit product_path(hero)
    assert_selector "button[data-action*='version-timeline#toggle']", wait: 6

    before = delete_top
    find("button[data-action*='version-timeline#toggle']", match: :first).click
    assert_selector "a", text: "비교 열기", wait: 6 # 패널 펼쳐짐
    after = delete_top
    assert_in_delta before, after, 2, "삭제버튼 top이 토글 전후 동일해야 함(#{before}→#{after})"

    # Fix1: 비교 열기 → 풀페이지 버전 비교(드로어 프레임에 갇히지 않음)
    click_on "비교 열기"
    assert_text "버전 비교", wait: 6
  end

  test "Fix2: 사이드바 '+' 새 폴더 → 사이드바에서 인라인 입력 등장·포커스" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    visit root_path
    within("aside") { find("button[title='새 폴더']").click }
    assert_selector "aside form input[name='product[name]']", wait: 6
    focused = page.evaluate_script("document.activeElement && document.activeElement.getAttribute('name')")
    assert_equal "product[name]", focused, "새 폴더 입력칸이 사이드바에서 포커스되어야 함"
  end
end
