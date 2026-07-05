require "application_system_test_case"

# Stage 5 P1: 사이드바 트리 검색 승격(서버 왕복 0). 접힌 <details> 속 leaf가 검색으로 드러나고
# (조상 자동 펼침), 폴더명도 매치되며, 카운트·✕/Esc 클리어·빈 결과가 동작하고, 클리어 시 원래 접힘
# 상태로 복원됨을 한 흐름으로 잠근다. 기본 로그인 = kim(owner·전 트리 가시).
class TreeSearchTest < ApplicationSystemTestCase
  def search_input = find("#app-sidebar input[data-tree-filter-target='input']")

  test "접힌 폴더 속 leaf 검색→조상 펼침·노출·카운트, 클리어 복원, 폴더명 매치, 빈 결과" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_selector "#app-sidebar", wait: 6

    # 초기: 루트 폴더 접힘 → 깊은 leaf(50ml, 레티놀>미국 하위)는 비가시. 폴더 요약명은 보임.
    within "#app-sidebar" do
      assert_text "레티놀 3% 세럼"
      assert_no_text "50ml"
    end

    # leaf 검색 → 조상(레티놀·미국) 자동 펼침으로 50ml 노출 + 매치 카운트 "1건". 무관 항목은 숨김.
    search_input.set("50ml")
    within "#app-sidebar" do
      assert_text "50ml"                     # 조상 펼침으로 가시화(갭 해소)
      assert_no_text "30ml"                  # 형제 leaf 무매치 → 숨김
      assert_no_text "비타민C 브라이트닝 앰플" # 무관 루트 폴더 숨김
      assert_selector "[data-tree-filter-target='count']", text: "1건"
    end

    # ✕ 클리어 → 입력 비움 + 원상복구(레티놀 다시 접힘 → 50ml 비가시, 전체 복귀).
    find("#app-sidebar button[data-tree-filter-target='clear']").click
    assert_equal "", search_input.value
    within "#app-sidebar" do
      assert_no_text "50ml"
      assert_text "비타민C 브라이트닝 앰플"
    end

    # 폴더명 매치(leaf 아님) → 폴더 1건. 요약 노출, 무관 루트 숨김.
    search_input.set("비타민C")
    within "#app-sidebar" do
      assert_text "비타민C 브라이트닝 앰플"
      assert_no_text "레티놀 3% 세럼"
      assert_selector "[data-tree-filter-target='count']", text: "1건"
    end

    # Esc 클리어 → 복구.
    search_input.send_keys(:escape)
    within("#app-sidebar") { assert_text "레티놀 3% 세럼" }

    # 빈 결과 → "일치하는 항목 없음" 1줄, 트리 숨김.
    search_input.set("존재하지않는품목zzz")
    within "#app-sidebar" do
      assert_text "일치하는 항목 없음"
      assert_no_text "레티놀 3% 세럼"
    end
  end
end
