require "application_system_test_case"

# Stage 4 T3/T4 브라우저 검증: scoped brand_admin(정브랜 @ 비타민C 브랜드)의 실제 저니 —
# 픽커 로그인 → 멤버 페이지에서 자기 브랜드 로스터(tenant-wide 계정 미표시) → 자기 브랜드 스코프 초대 발급.
# 브랜드 팀 페이지(/brands/:id) 헤더·멤버 요약도 함께 확인.
class BrandScopeTest < ApplicationSystemTestCase
  test "정브랜(scoped admin) 픽커 로그인 → 자기 브랜드 로스터 → 스코프 초대 발급" do
    system_sign_in("jung@cooa.dev") # 시드 6번째 페르소나 — brand_admin @ 비타민C 루트

    # 사이드바 "멤버" 링크가 scoped admin에게도 노출(can_view_members?)
    visit members_path

    # 로스터: 자기 브랜드 스코프 인원만(자신) · tenant-wide 계정(김쿠아) 미표시
    assert_text "정브랜"
    assert_no_text "김쿠아"

    # 스코프 초대 발급 — 폼엔 "전체 조직" 옵션 없음(scoped admin) · 자기 브랜드 제품만 선택 가능
    within "form[action='#{invitations_path}']" do
      fill_in "email", with: "brand-agency@vitc.dev"
      select "external_collaborator", from: "role_key"
      select "중국", from: "scope_product_id" # CO0100 (비타민C › 중국)
      click_button "초대 만들기"
    end

    assert_text "지금 복사해 전달하세요"
    assert_text "brand-agency@vitc.dev"

    inv = Invitation.find_by!(email: "brand-agency@vitc.dev")
    assert_equal Product.find_by!(code: "CO0100").id, inv.scope_product_id
  end

  test "브랜드 팀 페이지(/brands/:id) 헤더 + 스코프 멤버 요약" do
    # 기본 로그인 = kim(owner). 시카 브랜드 페이지엔 최디자(external @ CO0200) 요약.
    sica = Product.find_by!(name: "시카 수딩 크림")
    visit brand_path(id: sica.id)

    assert_text "브랜드 팀"
    assert_text "시카 수딩 크림"
    assert_text "최디자" # 스코프 멤버 요약 배지
    assert_text "멤버 관리" # owner라 관리 링크 노출
  end
end
