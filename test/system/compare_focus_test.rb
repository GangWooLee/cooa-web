require "application_system_test_case"

class CompareFocusTest < ApplicationSystemTestCase

  def comp = Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
  def scale_of
    page.evaluate_script(<<~JS)
      (() => { const s=document.querySelector("[data-artwork-viewer-target='stage']");
               const m=(s&&s.style.transform||"").match(/scale\\(([0-9.]+)\\)/); return m?parseFloat(m[1]):null })()
    JS
  end
  def dim_count
    page.evaluate_script("Array.from(document.querySelectorAll(\"[data-artwork-viewer-target='box']\")).filter(b=>parseFloat(getComputedStyle(b).opacity)<0.5).length")
  end

  test "비교: 초기 무선택(전 박스 선명) → 클릭 포커스 → 재클릭 흐림해제(줌 유지)" do
    page.current_window.resize_to(1440, 900)
    # 어노테이션이 있는 히어로 비교(v5→v6)
    from = comp.component_versions.find_by(version_number: 5)
    to   = comp.component_versions.find_by(version_number: 6)
    visit "/versions/#{from.id}/compare/#{to.id}"
    assert_selector "[data-artwork-viewer-target='box']", wait: 6
    sleep 0.7 # ready/fit
    assert_equal 0, dim_count, "초기엔 흐려진 박스 없음(무선택)"
    fit_scale = scale_of

    first = all("[data-artwork-viewer-target='box']").first
    first.click
    sleep 0.6
    assert dim_count.positive?, "포커스 시 비선택 박스 흐림"
    focus_scale = scale_of
    assert focus_scale > fit_scale, "포커스 시 확대(scale 증가): #{fit_scale}→#{focus_scale}"

    first.click # 같은 박스 재클릭
    sleep 0.6
    assert_equal 0, dim_count, "재클릭 시 흐림 해제(무선택)"
    assert_in_delta focus_scale, scale_of, 0.02, "재클릭해도 확대 유지(줌 안 되돌림)"
  end
end
