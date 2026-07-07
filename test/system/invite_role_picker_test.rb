require "application_system_test_case"

# 작업실 멤버 모달의 초대 역할 피커(3-tier 리프레임): 라디오-카드가 볼수만/편집/관리자 능력 설명 + 만료
# 안내를 노출하고, 역할 선택이 실제로 반영되는지. 기본 로그인=kim(owner·모달의 관리 폼 노출).
class InviteRolePickerTest < ApplicationSystemTestCase
  test "초대 모달: 3-tier 역할 카드 + 만료 안내 + 선택 동작" do
    page.current_window.resize_to(1440, 900)
    sica = Product.find_by!(name: "시카 수딩 크림")
    visit workspace_path(id: sica.workspace_id)
    assert_text "시카 수딩 크림", wait: 6

    find("button[aria-label='멤버 초대·관리']").click
    assert_selector "dialog[open]"

    within "dialog[open]" do
      assert_text "사람 추가"
      # 3-tier 명확화 — 능력-우선 문구가 카드에 가시.
      assert_text "볼 수만 있음"
      assert_text "편집 가능"
      assert_text "초대·구성원 관리"
      # 만료 투명성(사용자 질문에 대한 UI 답변).
      assert_text "7일간 유효"

      # 뷰어 카드 선택 → 해당 라디오 checked.
      find("label", text: "뷰어").click
      assert find("input[name='role_key'][value='viewer']", visible: :all).checked?
    end
  end
end
