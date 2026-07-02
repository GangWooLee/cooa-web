require "application_system_test_case"

# PDF 아트워크 E2E — 실무 파일(PDF)을 업로드해 PDF.js 캔버스로 충실히 렌더되고(종횡비 보존·비깨짐),
# 그 위에 %-정규화 피드백 박스를 남길 수 있는지. 좌표계는 표면 독립적이라 이미지와 동일 경로.
class PdfArtworkTest < ApplicationSystemTestCase
  def hero_component
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
  end

  # PDF.js 렌더 완료 대기 = 컨트롤러가 성공 후 dataset.rendered="1" 세팅(기본 300x150 캔버스와 구별).
  # 렌더 실패(import/worker 오류)면 세팅 안 되어 타임아웃 → 명확한 실패 신호.
  def wait_for_pdf_canvas
    Timeout.timeout(15) do
      until page.evaluate_script("(()=>{const c=document.querySelector(\"canvas[data-artwork-viewer-target='page']\");return c&&c.dataset.rendered==='1'})()")
        sleep 0.15
      end
    end
  end

  # 캔버스 컨테이너에 Shift+드래그 합성(onDown[shift]→startDraw→pointerup 실경로). 표면 무관(이미지와 동일).
  def shift_drag_on_viewer(from: 0.25, to: 0.7)
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

  test "PDF 업로드 → PDF.js 캔버스 렌더(종횡비 보존) → 피드백 박스 생성" do
    comp = hero_component
    visit new_component_component_version_path(comp)
    attach_file "component_version_artwork", Rails.root.join("test/fixtures/files/sample_artwork.pdf").to_s, make_visible: true
    fill_in "component_version_change_reason", with: "PDF 업로드 E2E"
    check "component_version_current"
    click_button "버전 추가"

    # PDF는 <img>가 아니라 <canvas>로 렌더
    assert_selector "canvas[data-artwork-viewer-target='page']", wait: 12
    assert_no_selector "[data-artwork-viewer-target='image']"
    wait_for_pdf_canvas

    # 종횡비 보존: 캔버스 비율이 PDF 페이지(1024x559)와 일치 → "비율 깨짐" 구조적 방지 검증
    ratio = page.evaluate_script("(()=>{const c=document.querySelector(\"canvas[data-artwork-viewer-target='page']\");return c.width/c.height})()")
    assert_in_delta 1024.0 / 559.0, ratio, 0.05, "캔버스 종횡비가 PDF 페이지와 일치해야(종횡비 보존)"

    # PDF 위에 피드백 박스(annotation) — 좌표계는 이미지와 동일(%-정규화)
    nv = comp.component_versions.order(:version_number).last
    before = nv.annotations.count
    shift_drag_on_viewer
    assert_selector "[data-version-feedback-target='newForm']", visible: true, wait: 4
    within("[data-version-feedback-target='newForm']") do
      select "인허가", from: "category"
      fill_in "body", with: "PDF 위 피드백"
      click_button "피드백 추가"
    end
    assert_text "PDF 위 피드백"
    assert_equal before + 1, nv.annotations.count
  end

  # F1/F4 회귀: (1) 스크리닝 화면도 PDF를 캔버스로 렌더(뷰어 locals 3종 전달), (2) 필름스트립 썸네일
  # 비율이 하드코드(2048:1118)가 아니라 실제 아트워크 비율로 교정. 비율 왜곡을 실증하기 위해
  # 히어로(1.832)와 전혀 다른 A4 세로(595×842, 0.707) fixture 사용.
  test "A4 세로 PDF: 스크리닝 화면 캔버스 렌더(F1) + 썸네일 비율 교정(F4)" do
    comp = hero_component
    visit new_component_component_version_path(comp)
    attach_file "component_version_artwork", Rails.root.join("test/fixtures/files/sample_artwork_a4.pdf").to_s, make_visible: true
    fill_in "component_version_change_reason", with: "A4 PDF E2E"
    click_button "버전 추가"
    assert_selector "canvas[data-artwork-viewer-target='page']", wait: 12
    wait_for_pdf_canvas
    nv = comp.component_versions.order(:version_number).last

    # (F1) 스크리닝 화면 — PDF 캔버스가 렌더되어야(이전엔 <img src=PDF>로 뷰어 데드)
    visit screening_component_version_path(nv)
    assert_selector "canvas[data-artwork-viewer-target='page']", wait: 12
    wait_for_pdf_canvas
    assert_no_selector "[data-artwork-viewer-target='image']"

    # (F4) 피드백 생성 → 필름스트립 썸네일 비율이 실제 아트워크(595/842) 기준으로 교정되는지
    visit component_version_path(nv)
    wait_for_pdf_canvas
    shift_drag_on_viewer
    assert_selector "[data-version-feedback-target='newForm']", visible: true, wait: 4
    within("[data-version-feedback-target='newForm']") do
      select "디자인", from: "category"
      fill_in "body", with: "A4 비율 검증"
      click_button "피드백 추가"
    end
    assert_text "A4 비율 검증"
    wait_for_pdf_canvas # 리로드 후 뷰어 ready(=correctThumbAspects 실행) 대기
    deviation = page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector(".av-thumb[data-w]")
        if (!t) return "NO_THUMB"
        const w = parseFloat(t.dataset.w), h = parseFloat(t.dataset.h)
        const expected = (w * 595) / (h * 842)
        const actual = parseFloat(t.style.aspectRatio)
        return Math.abs(actual - expected) / expected
      })()
    JS
    assert deviation != "NO_THUMB", "필름스트립 썸네일이 렌더되어야"
    assert deviation < 0.02, "썸네일 비율이 실제 아트워크(0.707) 기준으로 교정되어야 (편차 #{deviation})"
  end

  # F2 회귀: 이종 치수 비교(구버전 이미지 2048px vs 신버전 PDF 1024pt — 이미지→PDF 전환기의 현실
  # 시나리오). pane별 정규화 없이는 우측이 1/2 크기로 표시되고 피드백 좌표가 절반으로 오염된다.
  # 검증 = 같은 %-박스가 두 pane에서 동일한 화면 위치·크기로 정렬(정렬이 곧 draw 역변환의 정확성).
  test "이종 치수 비교: 이미지 pane과 PDF pane의 박스가 화면상 동일 위치로 정렬(F2)" do
    comp = hero_component
    v5 = comp.component_versions.find_by!(version_number: 5) # 이미지(2048×1118) + 시드 피드백 보유
    visit new_component_component_version_path(comp)
    attach_file "component_version_artwork", Rails.root.join("test/fixtures/files/sample_artwork.pdf").to_s, make_visible: true
    fill_in "component_version_change_reason", with: "혼합 비교 E2E"
    click_button "버전 추가"
    assert_selector "canvas[data-artwork-viewer-target='page']", wait: 12
    pdf_v = comp.component_versions.order(:version_number).last

    visit comparison_path(from_id: v5.id, to_id: pdf_v.id)
    assert_selector "[data-artwork-viewer-target='image']", wait: 12   # pane0 = 이미지
    wait_for_pdf_canvas                                                # pane1 = PDF 렌더 완료
    sleep 0.3 # 늦은 이미지 load → apply 재적용 여지

    metrics = page.evaluate_script(<<~JS)
      (() => {
        const panes = document.querySelectorAll("[data-artwork-viewer-target='pane']")
        if (panes.length < 2) return "PANES<2"
        const boxIn = (p) => p.querySelector("[data-artwork-viewer-target='box']")
        const b0 = boxIn(panes[0]), b1 = boxIn(panes[1])
        if (!b0 || !b1) return "NO_BOX"
        const r0 = b0.getBoundingClientRect(), r1 = b1.getBoundingClientRect()
        const p0 = panes[0].getBoundingClientRect(), p1 = panes[1].getBoundingClientRect()
        // pane 콘텐츠 원점 = rect + border(clientLeft/Top) — pane1의 border-l-2 보정
        const ox0 = p0.left + panes[0].clientLeft, ox1 = p1.left + panes[1].clientLeft
        const oy0 = p0.top + panes[0].clientTop,  oy1 = p1.top + panes[1].clientTop
        return { dx: Math.abs((r0.left - ox0) - (r1.left - ox1)),
                 dy: Math.abs((r0.top - oy0) - (r1.top - oy1)),
                 dw: Math.abs(r0.width - r1.width) }
      })()
    JS
    assert metrics.is_a?(Hash), "박스가 양 pane에 렌더되어야 (#{metrics})"
    assert metrics["dx"] < 2 && metrics["dy"] < 2 && metrics["dw"] < 2,
           "동일 %-박스가 두 pane에서 같은 화면 위치·크기여야(정규화) — 편차 #{metrics}"
  end
end
