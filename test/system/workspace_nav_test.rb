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

  # F1 회귀 저니(X4b): 작업실 진입 → 리프 드로어 → 버전 뷰 이동 → 버전 페이지 브레드크럼의 제품 링크
  # 클릭(풀 내비 복귀) → 본문(main)은 그 작업실 행만·타 작업실 부재 + 사이드바 헤더=작업실 컨텍스트.
  # 리프 상세 풀요청이 전 작업실 트리를 본문에 쏟아내던 결함(products_controller가 load_dashboard_rows를
  # workspace 인자 없이 호출)의 실브라우저 회귀 게이트. 통합(dashboard_body_scope_test)의 시스템 짝.
  test "리소스→버전→브레드크럼 복귀 시 본문·사이드바가 진입 작업실로 정합" do
    page.current_window.resize_to(1440, 900)
    co0001 = Product.find_by!(code: "CO0001") # 레티놀 › 일본(리프)

    # 작업실(레티놀) 진입 → 본문 트리 테이블. D2: 헤더 타이틀 = 작업실명(구 "데이터 관리").
    visit workspace_path(co0001.derived_workspace)
    assert_text "레티놀 3% 세럼", wait: 6

    # 리프(일본/CO0001) 드로어 열기 → 상세 로드(리프 행의 detail 프레임 링크 = 본문 <tr>에만 존재).
    find("tr[data-node-id='#{co0001.id}'] a[data-turbo-frame='detail']", match: :first).click
    within("#detail") { assert_text "구성요소", wait: 6 }

    # 드로어 버전 타임라인의 버전 칩 클릭 → Turbo.visit로 풀페이지 버전 뷰.
    find("#detail button[data-version-select-target='version']", match: :first).click

    # 버전 페이지 로드 = 브레드크럼의 제품(리프) 링크(복귀 트리거) 등장 → 클릭(product_path 풀 내비 복귀).
    find("a[href='#{product_path(co0001)}']", match: :first).click

    # 복귀 후 본문(main) = 진입 작업실(레티놀) 행만, 타 작업실(비타민C·시카) 부재 — 컨텍스트-본문 정합.
    within "main" do
      assert_text "레티놀 3% 세럼", wait: 6
      assert_no_text "비타민C 브라이트닝 앰플"
      assert_no_text "시카 수딩 크림"
    end
    # 동시에 사이드바 = 그 작업실 컨텍스트("모든 작업실" 백링크 + 그 작업실 트리 — 작업실명 텍스트는
    # 트리 루트 노드로 충족. 이름 고정행은 UX-트랙에서 삭제·메인 헤더 타이틀이 담당).
    within "#app-sidebar" do
      assert_text "모든 작업실"
      assert_text "레티놀 3% 세럼"
    end
  end
end
