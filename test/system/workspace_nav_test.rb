require "application_system_test_case"

# W1/W2 저니: 홈 작업실 카드 → 카드 클릭 진입 → 사이드바 컨텍스트 전환 확인 → 리프 열기(드로어) →
# "← 모든 작업실"로 홈 복귀. Figma식 컨텍스트 전환형 셸의 핵심 왕복. 기본 로그인 = kim(owner·전 트리 가시).
class WorkspaceNavTest < ApplicationSystemTestCase
  test "홈 카드 → 진입 → 컨텍스트 사이드바 → 리프 열기 → 모든 작업실 복귀" do
    page.current_window.resize_to(1440, 900)
    visit root_path

    # 홈 = 작업실 카드 목록.
    assert_text "데이터 관리", wait: 6
    within "main" do
      assert_text "레티놀 3% 세럼"
      assert_text "비타민C 브라이트닝 앰플"
      assert_text "시카 수딩 크림"
      click_link "레티놀 3% 세럼" # 카드 클릭 = 진입
    end

    # 진입 후: 사이드바 = 컨텍스트(작업실 헤더 + "모든 작업실" 백링크 + 그 작업실 트리).
    within "#app-sidebar" do
      assert_text "모든 작업실", wait: 6
      assert_text "레티놀 3% 세럼"
    end

    # 리프 열기(일본/CO0001) → 드로어에 상세 로드.
    co0001 = Product.find_by!(code: "CO0001")
    find("tr[data-node-id='#{co0001.id}'] a[data-turbo-frame='detail']", match: :first).click
    within("#detail") { assert_text "구성요소", wait: 6 }

    # "← 모든 작업실" → 홈 카드 복귀.
    within("#app-sidebar") { click_link "모든 작업실" }
    assert_text "데이터 관리", wait: 6
    within("main") { assert_text "비타민C 브라이트닝 앰플" } # 카드 목록으로 복귀
  end
end
