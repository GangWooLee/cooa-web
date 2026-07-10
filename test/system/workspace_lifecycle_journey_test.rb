require "application_system_test_case"

# 시나리오 ⑤ (D3 · 시스템): 홈 "새 작업실" 모달(이름 + 멤버 4종) → 빈 작업실 진입(빈 상태) → 툴바로 첫 폴더
# 생성(이 작업실 귀속 = JS workspace_id 스레딩) → 카드 우클릭 이름 변경(prompt→PATCH). 기본 로그인 = kim(owner).
class WorkspaceLifecycleJourneyTest < ApplicationSystemTestCase
  test "홈 새 작업실 모달(이름+멤버 4종) → 빈 상태 → 첫 폴더(작업실 귀속) → 카드 우클릭 이름변경" do
    choi = Account.find_by!(email: "choi@partner.example") # 비-전역 멤버 후보
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_text "작업실", wait: 6

    # 1) "새 작업실" → 모달 → 이름 + 멤버(최디자=관리자[4종 라벨]) → 만들기.
    click_button "새 작업실"
    within "dialog[open]" do
      fill_in "name", with: "리뉴얼 TF"
      find("input[name='member_ids[]'][value='#{choi.id}']").check
      select "관리자", from: "roles[#{choi.id}]"
      click_button "작업실 만들기"
    end

    # 2) 빈 작업실 진입 = 빈 상태. 멤버는 workspace-scope brand_admin으로 추가.
    assert_text "아직 폴더나 항목이 없습니다", wait: 6
    ws = Workspace.find_by!(name: "리뉴얼 TF")
    assert RoleAssignment.exists?(account: choi, scope_workspace_id: ws.id, role_key: "brand_admin"),
           "생성 시 선택 멤버 = 이 작업실 workspace-scope grant(관리자)"

    # 3) 툴바 "새 폴더"(미선택) → 이 작업실에 첫 루트 생성(빈 작업실 heal 아님 · JS가 workspace_id 스레딩).
    find("button.bg-cooa[title='새 폴더']").click
    inp = find("input[id^='node_name_']", wait: 6)
    first_root = Product.find(inp[:id][/\d+/])
    assert_equal ws.id, first_root.workspace_id, "첫 폴더는 이 작업실 루트로 귀속"

    # 4) 홈 복귀 → 카드 우클릭 → 이름 변경(prompt) → PATCH → 그 작업실 페이지(새 이름 헤더).
    # 카드(main)와 사이드바 링크가 같은 data-workspace-id를 가지므로 main으로 스코프.
    visit root_path
    within("main") { find("a[data-workspace-id='#{ws.id}']", wait: 6).right_click }
    accept_prompt(with: "리뉴얼 최종") do
      find("[data-workspace-ctx-target='menu'] button", text: "이름 변경").click
    end
    assert_text "리뉴얼 최종", wait: 6
    assert_equal "리뉴얼 최종", ws.reload.name
  end
end
