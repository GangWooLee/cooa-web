require "application_system_test_case"

# 대시보드 트리: 폴더 클릭=펼침/접힘, 이름변경=우클릭 메뉴, "· 하위 N" 제거
class DashboardCtxTest < ApplicationSystemTestCase

  def folder = Product.find_by(name: "레티놀 3% 세럼")

  test "폴더 이름 클릭 = 펼침/접힘(편집 아님)" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    f = folder
    child = f.children.first
    assert_selector "tr[data-node-id='#{child.id}']", wait: 6 # 펼쳐진 상태(자식 보임)
    within("tr[data-node-id='#{f.id}']") { find("[data-inline-edit-target='display']", text: f.name).click }
    assert_no_selector "tr[data-node-id='#{child.id}']", wait: 6 # 접힘(자식 숨김)
    assert_no_selector "input#node_name_#{f.id}" # 편집 안 됨
  end

  test "폴더 우클릭 → 메뉴 이름 변경 → 대시보드에서 인라인 입력" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    f = folder
    find("tr[data-node-id='#{f.id}']").right_click
    assert_text "이름 변경", wait: 6
    click_on "이름 변경"
    assert_selector "input#node_name_#{f.id}", wait: 6 # 대시보드(사이드바 아님)에서 입력 등장
  end

  test "'· 하위' 텍스트 제거" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_text "데이터 관리", wait: 6
    assert_no_text "· 하위"
  end
end
