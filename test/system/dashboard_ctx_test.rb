require "application_system_test_case"

# 작업실 트리 테이블(진입 후): 폴더 클릭=펼침/접힘, 이름변경=우클릭 메뉴, "· 하위 N" 제거.
# W1 이후 트리 테이블은 작업실 진입(/brands/:id) 화면에 렌더된다(홈은 작업실 카드).
class DashboardCtxTest < ApplicationSystemTestCase
  def folder = Product.find_by(name: "레티놀 3% 세럼")

  test "폴더 이름 클릭 = 펼침/접힘(편집 아님)" do
    page.current_window.resize_to(1440, 900)
    f = folder
    visit workspace_path(f.derived_workspace) # 작업실 진입 → 트리 테이블
    child = f.children.first
    assert_selector "tr[data-node-id='#{child.id}']", wait: 6 # 펼쳐진 상태(자식 보임)
    within("tr[data-node-id='#{f.id}']") { find("[data-inline-edit-target='display']", text: f.name).click }
    assert_no_selector "tr[data-node-id='#{child.id}']", wait: 6 # 접힘(자식 숨김)
    assert_no_selector "input#node_name_#{f.id}" # 편집 안 됨
  end

  test "폴더 우클릭 → 메뉴 이름 변경 → 트리 테이블에서 인라인 입력" do
    page.current_window.resize_to(1440, 900)
    f = folder
    visit workspace_path(f.derived_workspace)
    find("tr[data-node-id='#{f.id}']").right_click
    assert_text "이름 변경", wait: 6
    click_on "이름 변경"
    assert_selector "input#node_name_#{f.id}", wait: 6 # 트리 테이블(사이드바 아님)에서 입력 등장
  end

  test "'· 하위' 텍스트 제거" do
    page.current_window.resize_to(1440, 900)
    visit workspace_path(folder.derived_workspace)
    assert_text "레티놀 3% 세럼", wait: 6 # D2: 헤더 타이틀 = 작업실명(구 "데이터 관리")
    assert_no_text "· 하위"
  end
end
