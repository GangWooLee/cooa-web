require "application_system_test_case"

# 트리: 즉시 생성 → 트리에서 인라인 명명(Notion식, 드로어 안 띄움) · 자유 구성요소 · 연쇄삭제
class TreeCrudTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

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

  def create_folder_via_toolbar
    page.driver.browser.manage.window.resize_to(1440, 900)
    visit root_path
    within("[data-controller='menu']") do
      click_button "새로 만들기"
      click_button "새 폴더"
    end
    new_node # 대기 + 폴더 반환
  end

  test "즉시 생성 → 트리 인라인 명명 · 구성요소 · 연쇄삭제" do
    folder = create_folder_via_toolbar
    assert folder.folder?, "kind=folder 즉시 생성"
    assert_no_selector "#detail #product_name" # 드로어 안 띄움
    rename_in_tree(folder, "브랜드A")
    assert_selector "td", text: "브랜드A", wait: 5
    assert_equal "브랜드A", folder.reload.name

    # ── 폴더 행 "+"로 하위 항목 즉시 생성 → 빈 구성요소 + 트리 인라인 명명 ──
    js_click("tr[data-node-id='#{folder.id}'] button[title='하위 항목 추가']")
    item = new_node
    assert_equal folder.id, item.parent_id
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

    # ── 사이드바 "+" 즉시 루트 폴더 생성 → 트리 명명 ──
    visit root_path
    roots_before = Product.roots.count
    js_click("aside button[title='새 폴더']")
    new_node # 대기(생성 완료)
    assert_equal roots_before + 1, Product.roots.count, "사이드바 + → 루트 폴더"

    # ── 폴더 삭제(연쇄: 하위 항목·구성요소까지) ──
    iid = item.id
    cids = item.components.pluck(:id)
    visit root_path
    accept_confirm { js_click("tr[data-node-id='#{folder.id}'] button[title='삭제']") }
    assert_no_selector "td", text: "브랜드A", wait: 5
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

  test "진입점: 폴더 행 ⋯ 메뉴로 하위 폴더 즉시 생성" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    retinol = Product.find_by(name: "레티놀 3% 세럼")
    visit root_path
    before = retinol.children.count
    js_click("tr[data-node-id='#{retinol.id}'] button[title='이동']") # ⋯ 메뉴 토글
    js_click("tr[data-node-id='#{retinol.id}'] [data-menu-target='panel'] form[action='/products'] button") # 하위 폴더 추가
    child = new_node
    assert child.folder?
    assert_equal retinol.id, child.parent_id
    assert_equal before + 1, retinol.children.reload.count
  end

  test "리프 메타 인라인 편집(국가 자유 입력 + 정규화)" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    leaf = Product.find_by(code: "CO0001")
    visit product_path(leaf)
    within("#detail") do
      find("dd[data-controller='inline-edit'] span", exact_text: leaf.country_label).click # 국가(=일본) 정확 매칭
      fill_in "product_country", with: "미국"
      find("#product_country").send_keys(:enter)
    end
    assert_text "미국", wait: 5 # 풀 리렌더 대기
    assert_equal "US", leaf.reload.country, "미국 → US 정규화(screening 보존)"
  end
end
