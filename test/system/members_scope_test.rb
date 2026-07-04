require "application_system_test_case"

# Stage 3 (D4/D5) 브라우저 검증: members 화면에서 (1) 제품-스코프 초대 발급(제품 select → 1회용 링크 flash),
# (2) 로스터에 기존 스코프 grant(choi = external_collaborator @ CO0200[미국])가 "role@제품" 배지로 렌더.
# 기본 로그인 = kim(owner → manage_members 보유, 폼·배지 노출).
class MembersScopeTest < ApplicationSystemTestCase
  test "스코프 초대 발급(제품 선택) → 1회용 링크 노출 + 로스터 스코프 배지 렌더" do
    visit members_path

    # (2) 로스터: 시드 스코프 grant가 "role@제품" 배지로 — choi = external_collaborator @ 미국(CO0200)
    assert_text "external_collaborator @ 미국"

    # (1) 제품-스코프 초대 발급 — 초대 폼에 한정(인라인 grant 폼도 role_key/scope_product_id를 가지므로 within 필수)
    within "form[action='#{invitations_path}']" do
      fill_in "email", with: "agency-sys@partner.dev"
      select "external_collaborator", from: "role_key"
      select "중국", from: "scope_product_id" # CO0100 (비타민C 브라이트닝 앰플 › 중국)
      click_button "초대 만들기"
    end

    # 발급 직후: 1회용 초대 링크 배너 + 대기 목록에 신규 초대
    assert_text "지금 복사해 전달하세요"
    assert_text "agency-sys@partner.dev"

    # 발급된 초대가 실제 product 스코프인지 백엔드 확인
    inv = Invitation.find_by!(email: "agency-sys@partner.dev")
    assert_equal "product", inv.scope_type
    assert_equal Product.find_by!(code: "CO0100").id, inv.scope_product_id
  end
end
