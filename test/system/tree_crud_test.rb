require "application_system_test_case"

# 트리 CRUD(W1/W2): 작업실 진입 후 트리에서 즉시 생성 → 인라인 명명(Notion식) · 자유 구성요소 · DnD · 연쇄삭제.
# + 홈 "새 작업실"로 루트(작업실) 생성(기존 사이드바 + 루트 생성 의도 이식). 트리 테이블은 작업실 진입 화면에 렌더.
class TreeCrudTest < ApplicationSystemTestCase
  def retinol = Product.find_by!(name: "레티놀 3% 세럼")

  # 호버 노출(opacity-0) 컨트롤은 좌표 클릭이 불안정 → JS 클릭으로 견고하게
  def js_click(css)
    find(css, visible: :all).execute_script("this.click()")
  end

  # 생성 직후 트리에서 auto-focus된 인라인 입력칸(보이는 유일한 것) → 해당 노드.
  # 입력칸이 보일 때까지 대기 = 생성 커밋·리렌더 완료 보장(레이스 방지).
  def new_node
    inp = find("input[id^='node_name_']", wait: 5)
    Product.find(inp[:id][/\d+/])
  end

  def rename_in_tree(node, name)
    fill_in "node_name_#{node.id}", with: name
    find("#node_name_#{node.id}").send_keys(:enter)
  end

  # 트리 행 합성 드래그앤드롭(HTML5) — 좌표 클릭/Capybara drag는 불안정 → DragEvent 직접 디스패치
  def drag_row_onto(source_id, target_id, where: :middle)
    page.execute_script(<<~JS, source_id.to_s, target_id.to_s, where.to_s)
      const [sid, tid, where] = arguments
      const src = document.querySelector(`tr[data-node-id='${sid}']`)
      const tgt = document.querySelector(`tr[data-node-id='${tid}']`)
      const dt = new DataTransfer()
      const r = tgt.getBoundingClientRect()
      const y = where === 'top' ? r.top + 2 : where === 'bottom' ? r.bottom - 2 : r.top + r.height / 2
      const fire = (el, type) => el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt, clientY: y }))
      fire(src, 'dragstart'); fire(tgt, 'dragover'); fire(tgt, 'drop'); fire(src, 'dragend')
    JS
  end

  # 작업실 진입 후 툴바 폴더 아이콘(미선택 → 이 작업실에 루트 생성[복수 루트 수용·D3] → 인라인 명명 리다이렉트).
  def create_folder_via_toolbar
    page.current_window.resize_to(1440, 900)
    visit workspace_path(retinol.derived_workspace) # 작업실 진입 → 트리 테이블 + 툴바
    find("button.bg-cooa-gradient[title='새 폴더']").click # 툴바 폴더 아이콘(사이드바와 구분)
    new_node # 대기 + 폴더 반환
  end

  test "작업실 진입 후 즉시 생성 → 인라인 명명 · 구성요소 · 연쇄삭제 + 홈 새 작업실(빈 작업실) 생성" do
    folder = create_folder_via_toolbar
    assert folder.folder?, "kind=folder 즉시 생성"
    assert_no_selector "#detail #product_name" # 드로어 안 띄움
    rename_in_tree(folder, "브랜드A")
    assert_selector "td", text: "브랜드A", wait: 5
    assert_equal "브랜드A", folder.reload.name

    # ── 폴더 선택 → 상단 파일 아이콘으로 하위 항목 생성(선택 기준) ──
    find("tr[data-node-id='#{folder.id}']").click # 폴더 선택
    find("button[title='새 파일']").click
    item = new_node
    assert_equal folder.id, item.parent_id, "폴더 선택 → 자식"
    assert_equal 0, item.components.count, "새 항목은 빈 상태"
    rename_in_tree(item, "제품A")
    assert_selector "td", text: "제품A", wait: 5
    assert_equal "제품A", item.reload.name

    # ── 구성요소 추가(자유 이름) — 드로어에서. 업로드 플로우는 screens_test 에서 검증 ──
    visit product_path(item)
    within("#detail") { click_button "구성요소 추가" }
    assert_selector "#detail a[href$='/versions/new']", wait: 5
    assert_equal 1, item.components.reload.count
    assert_equal "제목 없음 구성요소", item.components.first.name, "자유 이름 기본값"

    # ── 홈 "새 작업실" → 모달 폼(이름) → 빈 작업실 생성·진입(빈 상태 유도) ──
    visit root_path # 홈 = 작업실 카드
    ws_before = Workspace.count
    click_button "새 작업실" # 모달 열기
    within "dialog[open]" do
      fill_in "name", with: "신규 작업실"
      click_button "작업실 만들기"
    end
    assert_text "아직 폴더나 항목이 없습니다", wait: 5 # 빈 작업실로 진입 = 빈 상태
    assert_equal ws_before + 1, Workspace.count, "홈 새 작업실 → 빈 작업실 생성(제품 0)"

    # ── 폴더 삭제(연쇄: 하위 항목·구성요소까지) — 그 작업실 트리에서(브랜드A는 레티놀 작업실의 2번째 루트) ──
    iid = item.id
    cids = item.components.pluck(:id)
    visit workspace_path(folder.derived_workspace) # 레티놀 작업실(브랜드A 포함)
    accept_confirm { js_click("tr[data-node-id='#{folder.id}'] button[title='삭제']") }
    assert_no_text "브랜드A", wait: 5 # 삭제 후 그 작업실 트리 복귀(브랜드A 부재) = 완료 대기(레이스 방지)
    assert_not Product.exists?(folder.id), "폴더 삭제"
    assert_not Product.exists?(iid), "하위 항목 연쇄삭제"
    assert_empty Component.where(id: cids), "구성요소 연쇄삭제"
  end

  test "트리 인라인 명명 Esc 취소 → 기본명 유지(폼 숨김)" do
    folder = create_folder_via_toolbar
    find("#node_name_#{folder.id}").send_keys("draft", :escape)
    assert_selector "td", text: "제목 없음 폴더", wait: 5 # 취소 → 기본명 유지
    assert_no_selector "input#node_name_#{folder.id}" # 폼 숨김
    assert_equal "제목 없음 폴더", folder.reload.name
  end

  test "빈 이름 → 기본명 유지(빈값 가드)" do
    folder = create_folder_via_toolbar
    find("#node_name_#{folder.id}").send_keys(:backspace, :enter) # 자동선택 삭제 후 Enter → 빈값 가드
    assert_selector "td", text: "제목 없음 폴더", wait: 5
    assert_equal "제목 없음 폴더", folder.reload.name
  end

  test "선택 기준 생성: 폴더 선택 → 상단 폴더 아이콘 = 자식" do
    page.current_window.resize_to(1440, 900)
    r = retinol
    visit workspace_path(r.derived_workspace) # 작업실 진입
    before = r.children.count
    find("tr[data-node-id='#{r.id}']").click # 작업실 루트 폴더 선택
    find("button.bg-cooa-gradient[title='새 폴더']").click
    child = new_node
    assert child.folder?
    assert_equal r.id, child.parent_id, "폴더 선택 → 자식"
    assert_equal before + 1, r.children.reload.count
  end

  test "드래그앤드롭: 리프를 같은 작업실 다른 폴더 안으로 이동(재배치)" do
    page.current_window.resize_to(1440, 900)
    r = retinol
    leaf = Product.find_by!(code: "CO0001")      # 레티놀 › 일본(리프)
    dest = r.children.find_by!(name: "미국")      # 레티놀 › 미국(폴더) — 같은 작업실
    visit workspace_path(r.derived_workspace)
    drag_row_onto(leaf.id, dest.id, where: :middle) # 폴더 가운데 = 안으로
    assert_selector "tr[data-node-id='#{leaf.id}'][data-parent-id='#{dest.id}']", wait: 5 # 재렌더 후
    assert_equal dest.id, leaf.reload.parent_id
  end

  test "리프 메타 인라인 편집(국가 select — 표시=한글·저장=코드)" do
    page.current_window.resize_to(1440, 900)
    leaf = Product.find_by(code: "CO0001")
    visit product_path(leaf)
    assert_selector "#detail", wait: 10
    sleep 0.3 # Stimulus 연결 정착(무거운 대시보드 뒤 드로어)
    within("#detail") do
      # 국가(=일본) 편집 열기 — 클릭이 Stimulus 연결 전일 수 있어 재시도
      3.times do
        find("dd[data-controller='inline-edit'] span", exact_text: leaf.country_label).click
        break if has_css?("#product_country", wait: 3)
      end
      select "미국", from: "product_country" # 드롭다운(한글 라벨) 선택 → change 저장
    end
    assert_text "미국", wait: 10 # 풀 리렌더 대기
    assert_equal "US", leaf.reload.country, "선택값=코드(US) 저장(screening 보존)"
  end
end
