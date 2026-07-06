require "application_system_test_case"

# D2/D1 실브라우저 인터랙션: (1) 멤버 어포던스 팝오버 열기→초대 폼 노출→Esc 닫힘(popover 컨트롤러·dismissable),
# (2) flash 토스트 ✕ 수동 닫기(클릭 구동 — 자동 소멸 타이머 대기 아님). 기본 로그인 = kim(owner).
class HeaderPopoverTest < ApplicationSystemTestCase
  test "멤버 팝오버: 트리거 클릭 → 초대 폼 노출 → Esc로 닫힘" do
    page.current_window.resize_to(1440, 900)
    sica = Product.find_by!(name: "시카 수딩 크림")
    visit workspace_path(id: sica.workspace_id)
    assert_text "시카 수딩 크림", wait: 6 # 헤더 로드 앵커

    # 닫힘 상태 = 패널 내용 미노출(native details 접힘).
    assert_no_text "이 작업실에 초대"
    find("summary[aria-label='멤버 초대·관리']").click
    assert_text "이 작업실에 초대" # 열림 = 초대 폼 노출

    # Esc → 팝오버 닫힘(document keydown → popover#hide가 open 제거).
    find("body").send_keys(:escape)
    assert_no_text "이 작업실에 초대"
  end

  test "flash 토스트: notice ✕로 수동 닫힘(결정적 · 타이머 대기 아님)" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_text "데이터 관리", wait: 6

    # 작업실 생성 → 리다이렉트가 notice("작업실을 만들었습니다") = 우상단 토스트를 남긴다.
    click_button "새 작업실"
    within "dialog[open]" do
      fill_in "name", with: "토스트 확인 TF"
      click_button "작업실 만들기"
    end

    # 토스트를 ✕로 즉시 닫는다(자동 소멸 4s와 무관 — 클릭이 제거를 구동).
    toast = find("[role='status']", text: "작업실을 만들었습니다", wait: 6)
    within(toast) { find("button[aria-label='닫기']").click }
    assert_no_text "작업실을 만들었습니다"
  end
end
