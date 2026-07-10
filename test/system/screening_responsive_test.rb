require "application_system_test_case"

class ScreeningResponsiveTest < ApplicationSystemTestCase
  def hero_v5
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: 5)
  end

  test "모바일 스크리닝 결과는 액션바 위에서 별도 스크롤된다" do
    page.current_window.resize_to(390, 844)
    visit screening_component_version_path(hero_v5)
    assert_text "스크리닝 결과"
    assert_selector "[data-screening-target='finding']", minimum: 1

    initial = screening_metrics
    assert_equal initial["scrollBottom"], initial["actionTop"], "결과 스크롤 영역과 액션바가 겹치지 않아야 함"
    assert_operator initial["scrollHeight"], :>, initial["scrollClientHeight"], "모바일 결과 영역은 자체 스크롤을 가져야 함"

    page.execute_script(<<~JS)
      const scroll = document.querySelector("[data-controller='screening'] > div:nth-of-type(2)")
      scroll.scrollTop = scroll.scrollHeight
    JS

    scrolled = screening_metrics
    assert scrolled["lastBottom"] <= scrolled["actionTop"], "마지막 finding 카드가 액션바 아래에 가려지면 안 됨"
  end

  private

  def screening_metrics
    page.evaluate_script(<<~JS)
      (() => {
        const scroll = document.querySelector("[data-controller='screening'] > div:nth-of-type(2)")
        const action = document.querySelector(".screening-actionbar")
        const findings = Array.from(document.querySelectorAll("[data-screening-target='finding']"))
        const last = findings[findings.length - 1]
        const sr = scroll.getBoundingClientRect()
        const ar = action.getBoundingClientRect()
        const lr = last.getBoundingClientRect()
        return {
          scrollClientHeight: scroll.clientHeight,
          scrollHeight: scroll.scrollHeight,
          scrollBottom: Math.round(sr.bottom),
          actionTop: Math.round(ar.top),
          lastBottom: Math.round(lr.bottom)
        }
      })()
    JS
  end
end
