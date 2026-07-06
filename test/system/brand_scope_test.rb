require "application_system_test_case"

# Stage 4 T3/T4 + W3 브라우저 검증: 작업실 페이지(/brands/:id)의 인라인 멤버 관리 —
# (1) scoped brand_admin(정브랜 @ 비타민C)이 자기 작업실 페이지에서 초대 발급(범위 선택 없음 · 서버가 이
#     작업실로 스코프), (2) tenant-wide owner(kim)의 작업실 헤더·멤버 요약·관리 패널.
# 초대 발급은 이제 전사 관리(/members)가 아니라 그 작업실 페이지에서 일어난다(컨텍스트 유지).
class BrandScopeTest < ApplicationSystemTestCase
  test "정브랜(scoped admin): 자기 작업실 페이지에서 초대 — 범위 선택 없음·작업실로 스코프" do
    system_sign_in("jung@cooa.dev") # 시드 6번째 페르소나 — brand_admin @ 비타민C 루트
    vitc = Product.find_by!(name: "비타민C 브라이트닝 앰플")
    visit workspace_path(vitc.derived_workspace)

    assert_text "비타민C 브라이트닝 앰플"                  # D2 헤더 작업실명
    assert_selector "summary[aria-label='멤버 초대·관리']"  # 멤버 어포던스 트리거(구 "작업실" 배지 대체)

    # 인라인 멤버 관리 팝오버 열기(전사 관리로 이탈 없음) → 초대 폼엔 범위 select 부재
    find("summary[aria-label='멤버 초대·관리']").click
    within "form[action='#{invitations_path}']" do
      assert_no_selector "select[name='scope_product_id']", visible: :all
      fill_in "email", with: "brand-agency@vitc.dev"
      select "외부 협력", from: "role_key" # external_collaborator(D4 라벨) — 작업실 폼은 4종만
      click_button "초대 만들기"
    end

    assert_text "지금 복사해 전달하세요"
    inv = Invitation.find_by!(email: "brand-agency@vitc.dev")
    assert_equal [ "workspace", vitc.workspace_id ], [ inv.scope_type, inv.scope_workspace_id ] # 이 작업실로 스코프 — 서버 강제
  end

  test "작업실 페이지(/brands/:id) 헤더 + 멤버 요약 + 관리 패널(owner)" do
    # 기본 로그인 = kim(owner). 시카 작업실 페이지엔 최디자(external @ CO0200) 요약 + 관리 패널.
    sica = Product.find_by!(name: "시카 수딩 크림")
    visit workspace_path(id: sica.workspace_id)

    assert_text "시카 수딩 크림"                          # D2 헤더 작업실명
    assert_selector "summary[aria-label='멤버 초대·관리']"  # 멤버 어포던스 트리거(구 "작업실" 배지 대체)

    # 관리 권한자(owner)에겐 인라인 멤버 관리 팝오버(구 "멤버 관리" 이탈 링크 대체) — 열면 멤버 요약 + 초대 폼
    find("summary[aria-label='멤버 초대·관리']").click
    assert_text "최디자"          # 스코프 멤버 요약(패널 내부로 이관)
    assert_text "이 작업실에 초대" # 초대 폼
  end
end
