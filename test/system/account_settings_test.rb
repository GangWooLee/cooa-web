require "application_system_test_case"

# 계정 메뉴(사이드바 상단 드롭다운) → 계정 설정 → 프로필 이름 편집 → 사이드바 반영. 기본 로그인=kim(owner).
class AccountSettingsTest < ApplicationSystemTestCase
  test "계정 메뉴 → 계정 설정 → 이름 편집 → 사이드바 반영" do
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_text "작업실", wait: 6

    # 사이드바 계정 메뉴(네이티브 <details>) 열기 → 계정 설정 진입.
    within "#app-sidebar" do
      find("summary[aria-haspopup='true']").click
      click_link "계정 설정"
    end
    assert_text "계정 설정", wait: 6
    assert_text "프로필"
    assert_text kim_email # 계정 정보(읽기)

    # 이름 편집 + 저장.
    fill_in "account[display_name]", with: "쿠아 김편집"
    click_button "저장"
    assert_text "프로필이 저장되었습니다", wait: 6

    # 사이드바 계정 메뉴 트리거가 새 이름 반영(account 우선 표시 해석).
    within "#app-sidebar" do
      assert_text "쿠아 김편집"
    end
  end

  private

  def kim_email = "kim@cooa.dev"
end
