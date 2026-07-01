require "application_system_test_case"

# 리프레임 E2E — 피드백(annotation): (Point 4) 단일 버전 뷰에서도 Shift+드래그로 남기고,
# 리뷰어가 반영 확인(resolve)/다시 열기. "사용자가 의도대로 경험" + 부정 쌍둥이(권한 게이팅).
class VersionFeedbackTest < ApplicationSystemTestCase
  def hero_v5
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: 5)
  end

  # 뷰어 ready(이미지 로드 + nat 세팅) 대기 — 그 전엔 draw 좌표가 NaN이라 draw 이벤트 미발화(결정적 게이트).
  def wait_for_viewer_ready
    Timeout.timeout(6) do
      until page.evaluate_script("(()=>{const i=document.querySelector(\"[data-artwork-viewer-target='image']\");return !!(i&&i.complete&&i.naturalWidth>0)})()")
        sleep 0.1
      end
    end
  end

  # 캔버스에 Shift+드래그 합성(뷰어 onDown[shift]→startDraw→pointerup 실제 경로 구동)
  def shift_drag_on_viewer(from: 0.2, to: 0.75)
    page.execute_script(<<~JS, from, to)
      const [f, t] = arguments
      const canvas = document.querySelector("[data-artwork-viewer-target='canvas']")
      const panes = document.querySelectorAll("[data-artwork-viewer-target='pane']")
      const r = panes[panes.length - 1].getBoundingClientRect()
      const ev = (type, fx, fy, extra) => new PointerEvent(type, Object.assign(
        { clientX: r.left + r.width * fx, clientY: r.top + r.height * fy, bubbles: true, cancelable: true }, extra || {}))
      canvas.dispatchEvent(ev("pointerdown", f, f, { shiftKey: true }))
      window.dispatchEvent(ev("pointermove", t, t))
      window.dispatchEvent(ev("pointerup", t, t))
    JS
  end

  # ① 단일 버전 뷰에서 Shift+드래그 피드백 남기기(Point 4)
  test "단일 버전 뷰에서 Shift+드래그로 피드백 남기기(Point 4)" do
    v5 = hero_v5
    before = v5.annotations.count
    visit component_version_path(v5) # 김쿠아(owner)=leave_feedback 보유
    assert_text "피드백"
    assert_selector "[data-artwork-viewer-target='image']"
    wait_for_viewer_ready

    shift_drag_on_viewer

    # 새 피드백 폼 등장(onDraw) → 입력 → 추가
    assert_selector "[data-version-feedback-target='newForm']", visible: true, wait: 4
    within("[data-version-feedback-target='newForm']") do
      select "인허가", from: "category"
      fill_in "body", with: "E2E 자동 피드백"
      click_button "피드백 추가"
    end

    # 사용자-가시 결과: 목록에 새 항목 + 카운트 증가 (+ DB 확증)
    assert_text "E2E 자동 피드백"
    assert_text "피드백 (#{before + 1})"
    assert_equal before + 1, v5.annotations.count
  end

  # ③ 리뷰어가 피드백 반영 확인(resolve) → 다시 열기(reopen)
  test "리뷰어가 피드백 반영 확인(resolve) → 다시 열기" do
    v5 = hero_v5
    system_sign_in("lee@cooa.dev") # ra_reviewer → resolve_feedback 보유
    ann = v5.annotations.open.first
    assert ann, "시드에 미반영 피드백 존재 전제"

    visit component_version_path(v5)
    open_feedback_detail(ann.seq)
    within(detail_of(ann.seq)) { click_button "✓ 반영됨으로 표시" }

    # PATCH+리로드 완료를 가시 신호로 대기(즉시 DB 조회는 레이스) — 상세 재오픈 시 반영확인/다시열기 노출
    open_feedback_detail(ann.seq)
    within(detail_of(ann.seq)) do
      assert_text "반영 확인"
      assert_button "다시 열기"
    end
    assert ann.reload.resolved?, "resolve 시 resolved 되어야 함"

    # reopen → 리로드 후 resolve 버튼 복귀를 가시 신호로 대기
    within(detail_of(ann.seq)) { click_button "다시 열기" }
    open_feedback_detail(ann.seq)
    within(detail_of(ann.seq)) { assert_button "✓ 반영됨으로 표시" }
    assert ann.reload.open?, "reopen 시 open 되어야 함"
  end

  # 부정: contributor(박쿠아)는 반영 확인 버튼 부재(권한 게이팅)
  test "contributor는 반영 확인 버튼 부재(권한 게이팅)" do
    v5 = hero_v5
    system_sign_in("park@cooa.dev") # contributor → resolve_feedback 없음
    ann = v5.annotations.open.first
    visit component_version_path(v5)
    open_feedback_detail(ann.seq)
    within(detail_of(ann.seq)) { assert_no_button "✓ 반영됨으로 표시" }
  end

  private

  def open_feedback_detail(seq)
    within("[data-version-feedback-target='list']") { find("button[data-seq='#{seq}']").click }
  end

  def detail_of(seq) = "[data-version-feedback-target='detail'][data-seq='#{seq}']"
end
