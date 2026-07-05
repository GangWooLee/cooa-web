require "application_system_test_case"

# W2 이후 사이드바 트리 검색은 **작업실 진입 후** 컨텍스트 트리(그 작업실 서브트리)에서 동작한다(서버 왕복 0).
# 접힌 <details> 속 leaf가 검색으로 드러나고(조상 자동 펼침), 폴더명도 매치되며, 카운트·✕/Esc 클리어·빈 결과가
# 동작하고, 클리어 시 원래 접힘 상태로 복원됨을 한 흐름으로 잠근다. 레티놀 작업실(레티놀 › 미국 › 30ml/50ml, 일본).
class TreeSearchTest < ApplicationSystemTestCase
  def search_input = find("#app-sidebar input[data-tree-filter-target='input']")

  test "작업실 진입 후 접힌 폴더 속 leaf 검색→조상 펼침·노출·카운트, 클리어 복원, 폴더명 매치, 빈 결과" do
    page.current_window.resize_to(1440, 900)
    visit workspace_path(Product.find_by!(name: "레티놀 3% 세럼").derived_workspace) # 작업실 진입 → 컨텍스트 사이드바
    assert_selector "#app-sidebar", wait: 6

    # 초기: 작업실 루트 폴더 접힘 → 깊은 leaf(50ml, 미국 하위)는 비가시. 루트 요약명은 보임.
    within "#app-sidebar" do
      assert_text "레티놀 3% 세럼"
      assert_no_text "50ml"
    end

    # leaf 검색 → 조상(미국) 자동 펼침으로 50ml 노출 + 매치 카운트 "1건". 형제 leaf는 숨김.
    search_input.set("50ml")
    within "#app-sidebar" do
      assert_text "50ml"                     # 조상 펼침으로 가시화(갭 해소)
      assert_no_text "30ml"                  # 형제 leaf 무매치 → 숨김
      assert_selector "[data-tree-filter-target='count']", text: "1건"
    end

    # ✕ 클리어 → 입력 비움 + 원상복구(미국 다시 접힘 → 50ml 비가시).
    find("#app-sidebar button[data-tree-filter-target='clear']").click
    assert_equal "", search_input.value
    within "#app-sidebar" do
      assert_no_text "50ml"
      assert_text "레티놀 3% 세럼"
    end

    # 폴더명 매치(leaf 아님) → 폴더 1건. 요약 노출.
    search_input.set("미국")
    within "#app-sidebar" do
      assert_text "미국"
      assert_selector "[data-tree-filter-target='count']", text: "1건"
    end

    # Esc 클리어 → 복구.
    search_input.send_keys(:escape)
    within("#app-sidebar") { assert_text "레티놀 3% 세럼" }

    # 빈 결과 → "일치하는 항목 없음" 1줄, 트리 숨김.
    search_input.set("존재하지않는품목zzz")
    within "#app-sidebar" do
      assert_text "일치하는 항목 없음"
      assert_no_text "미국"
    end
  end
end
