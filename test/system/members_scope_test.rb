require "application_system_test_case"

# W3/W4 전사 관리(/members) 브라우저 검증: (1) 로스터의 제품-스코프 grant가 "role · 작업실명"(소속 작업실)
# 배지로 렌더 — choi(external_collaborator @ CO0200)의 작업실 루트는 "시카 수딩 크림". (2) 전사 초대 폼엔
# 범위(작업실) select가 없다 — 전사 멤버(모든 작업실 접근)만 발급하고, 작업실 한정 초대는 각 작업실 페이지로
# 이동(brand_scope_test). 기본 로그인 = kim(owner → manage_members·전사 초대 가능).
class MembersScopeTest < ApplicationSystemTestCase
  test "전사 관리 로스터 소속-작업실 배지 + 전사 초대(범위 선택 없음)" do
    visit members_path

    # (1) 로스터: 시드 스코프 grant가 "역할 라벨 · 작업실 링크" 배지로 — CO0200의 작업실 루트 = 시카 수딩 크림.
    # D4: 배지는 한글 라벨(외부 협력) · D5: 작업실명은 읽기전용 링크(회수·추가 폼 은퇴).
    assert_text "외부 협력"
    assert_link "시카 수딩 크림"

    # (2) 전사 초대 폼 — 범위(scope_product_id) select 부재. email + 역할(7종·한글 라벨)만.
    within "form[action='#{invitations_path}']" do
      assert_no_selector "select[name='scope_product_id']", visible: :all
      fill_in "email", with: "org-sys@partner.dev"
      select "멤버", from: "role_key" # contributor(라벨=멤버)
      click_button "전사 초대 만들기"
    end

    # 발급 직후: 1회용 링크 배너 + 백엔드는 tenant 스코프(전사)
    assert_text "지금 복사해 전달하세요"
    inv = Invitation.find_by!(email: "org-sys@partner.dev")
    assert_equal "tenant", inv.scope_type
    assert_nil inv.scope_product_id
  end
end
