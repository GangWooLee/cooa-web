require "application_system_test_case"

# 화면 캡처 + 핵심 인터랙션(뷰어 포커스) 검증
class ScreensTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  def hero
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
  end

  # HTML5 드래그앤드롭 합성(동일 DataTransfer가 dragstart→drop 통과) — Selenium 네이티브 DnD 불안정 회피
  def drag_drop(src, tgt)
    page.execute_script(<<~JS, src, tgt)
      const [s, t] = arguments
      const dt = new DataTransfer()
      const fire = (el, ty) => el.dispatchEvent(new DragEvent(ty, { dataTransfer: dt, bubbles: true, cancelable: true }))
      fire(s, 'dragstart'); fire(t, 'dragover'); fire(t, 'drop'); fire(s, 'dragend')
    JS
  end

  test "capture screens" do
    dir = Rails.root.join("tmp/screens")
    FileUtils.mkdir_p(dir)
    v5 = hero.component_versions.find_by(version_number: 5)
    v6 = hero.component_versions.find_by(version_number: 6)

    visit root_path
    assert_text "레티놀 3% 세럼"
    # 상단바 정합: 첫 히스토리 탭 우측 ≈ 사이드바 우측 (격자 일치)
    # 탭은 div 컨테이너(코드 링크 + 버전 칩 링크 — 중첩 a 금지로 언네스트됨)
    assert_selector "header nav > div", minimum: 1
    assert_selector "header nav a", minimum: 1 # 칩/코드 링크 존재
    tab_r  = page.evaluate_script("document.querySelector('header nav > div').getBoundingClientRect().right")
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
    assert_selector "[data-vs-ready]" # version-select 컨트롤러 연결 대기
    assert_no_selector "a[href*='/compare/']" # 변경사유 콜아웃 기본 접힘
    # 슬롯 채우기 = 드래그앤드롭(클릭 채움 폐기). 같은 구성요소 두 버전 → [비교 열기] 활성
    nodes = all("button[data-version-select-target='version']")
    slot_a = find("button[data-slot='a']")
    slot_b = find("button[data-slot='b']")
    drag_drop(nodes[0], slot_a) # 단상자 V1 → 슬롯 a
    drag_drop(nodes[1], slot_b) # 단상자 V2 → 슬롯 b
    assert_selector "button[data-version-select-target='compareBtn']:not([disabled])"
    save_screenshot(dir.join("2_product.png"))
    # 다른 구성요소 드롭 → 상대 슬롯 비움(비활성)
    drag_drop(nodes[6], slot_a) # 용기 V1 → a (b가 단상자라 비워짐)
    assert_selector "button[data-version-select-target='compareBtn'][disabled]"
    drag_drop(nodes[7], slot_b) # 용기 V2 → b (같은 구성요소) → 활성
    assert_selector "button[data-version-select-target='compareBtn']:not([disabled])"
    # 슬롯 클릭 → 초기화(비움) → 비활성
    slot_a.click
    assert_selector "button[data-version-select-target='compareBtn'][disabled]"
    # ▾ 변경사유(담당자별 어노테이션) 펼침 — 단상자 v5→v6 = 5건
    find("button[aria-controls='reason-#{hero.id}-5']").click
    sleep 0.3
    assert_selector "button[data-version-timeline-target='dot'].dot-on", minimum: 1 # 선택 상태 보임(①)
    within("#reason-#{hero.id}-5") do
      assert_selector "li", minimum: 2       # 담당자별 항목(②)
      assert_selector "a[href*='/compare/']" # 비교 열기
    end
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

  # 버전 파일: 보기(전체 페이지) · 추가(업로드) · 수정(교체)
  test "version file: view, add, edit" do
    dir = Rails.root.join("tmp/screens")
    FileUtils.mkdir_p(dir)
    page.driver.browser.manage.window.resize_to(1440, 900)
    prod    = Product.find_by(code: "CO0001")
    barcode = prod.components.find_by(component_type: "barcode") # 원래 아트워크 없음

    # ── v# 칩 클릭 → 파일 보기(전체 페이지, 드로어 아님) ──
    visit product_path(prod)
    assert_selector "[data-vs-ready]" # version-select 연결 대기
    nodes = all("button[data-version-select-target='version']")
    assert_operator nodes.size, :>, 0
    nodes.first.execute_script("this.click()") # draggable이라 합성 click(드래그 아님)
    assert_current_path(%r{/versions/\d+\z}, wait: 5)
    assert_selector "button", text: "전체"                       # show 줌바(zoom:true) — screening/compare엔 없음
    assert_selector "[data-controller='artwork-viewer'] img"     # 뷰어 렌더
    save_screenshot(dir.join("7_version_show.png"))

    # ── 새 버전 추가(업로드) ── 드로어 타임라인 "+ 새 버전" 진입점
    visit product_path(prod)
    assert_selector "[data-vs-ready]"
    add_link = "a[href='/components/#{barcode.id}/versions/new']"
    assert_selector add_link
    find(add_link).click
    assert_current_path(%r{/components/#{barcode.id}/versions/new\z}, wait: 5)
    attach_file "component_version_artwork", Rails.root.join("test/fixtures/files/box.jpg").to_s, make_visible: true
    fill_in "component_version_change_reason", with: "바코드 초안 업로드"
    check "component_version_current"
    save_screenshot(dir.join("8_version_new.png"))
    click_button "버전 추가"
    assert_current_path(%r{/versions/\d+\z}, wait: 5)
    assert_selector "img[src*='/rails/active_storage/']", wait: 5 # 업로드 파일(ActiveStorage) 렌더
    nv = barcode.component_versions.order(:version_number).last
    assert nv.artwork.attached?, "새 버전에 아트워크 첨부됨"
    assert nv.current?, "새 버전이 현재 버전"
    assert_equal 1, barcode.component_versions.where(current: true).count, "current 단일성 보장"

    # ── 대시보드 칩 갱신(현재 버전 = 방금 추가본) ──
    visit root_path
    assert_selector "a[href='/versions/#{nv.id}']", wait: 5

    # ── 수정: 파일 교체 ──
    visit edit_component_version_path(nv)
    attach_file "component_version_artwork", Rails.root.join("test/fixtures/files/box2.jpg").to_s, make_visible: true
    click_button "저장"
    assert_current_path(%r{/versions/#{nv.id}\z}, wait: 5)
    assert_selector "img[src*='/rails/active_storage/']", wait: 5
  end
end
