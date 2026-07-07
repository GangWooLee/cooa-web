require "application_system_test_case"

# Stage 4 T3/T4 + W3 + V1~V3 브라우저 검증: 작업실 페이지의 인라인 멤버 모달(구 팝오버 승격) —
# (1) scoped brand_admin(정브랜 @ 비타민C)이 자기 작업실 모달에서 미지 이메일 추가 → 초대 링크 발급(범위 선택
#     없음 · 서버가 이 작업실로 스코프), (2) tenant-wide owner(kim)의 멤버 모달(멤버 목록 + 사람 추가 폼),
# (3) 제안 목록에서 동료 선택 → 즉시 grant(초대 미생성) → 멤버 목록 반영. 멤버 추가는 이제 통합 모달의 "사람
#     추가" 폼(→ /workspace_memberships)이 서버에서 즉시추가/초대를 자동 분기한다.
class BrandScopeTest < ApplicationSystemTestCase
  test "정브랜(scoped admin): 자기 작업실 모달에서 미지 이메일 → 초대 링크 발급(작업실 스코프·범위 선택 없음)" do
    system_sign_in("jung@cooa.dev") # 시드 6번째 페르소나 — brand_admin @ 비타민C 루트
    page.current_window.resize_to(1440, 900)
    vitc = Product.find_by!(name: "비타민C 브라이트닝 앰플")
    visit workspace_path(vitc.derived_workspace)

    assert_text "비타민C 브라이트닝 앰플", wait: 6              # D2 헤더 작업실명
    assert_selector "button[aria-label='멤버 초대·관리']"       # 멤버 어포던스 트리거(구 summary 팝오버 대체)

    # 인라인 멤버 모달 열기(전사 관리로 이탈 없음) → 사람 추가 폼엔 범위 select 부재.
    find("button[aria-label='멤버 초대·관리']").click
    within "dialog[open]" do
      assert_no_selector "select[name='scope_product_id']", visible: :all
      fill_in "email", with: "brand-agency@vitc.dev"   # 미지 이메일(addable 아님) → 초대 분기
      find("label", text: "외부 협력").click              # external_collaborator — 라디오-카드 피커(작업실 폼 4종)
      click_button "추가"
    end

    assert_text "지금 복사해 전달하세요", wait: 6              # 발급 링크 배너(모달 자동 재열림)
    inv = Invitation.find_by!(email: "brand-agency@vitc.dev")
    assert_equal [ "workspace", vitc.workspace_id ], [ inv.scope_type, inv.scope_workspace_id ] # 이 작업실로 스코프 — 서버 강제
  end

  test "작업실 멤버 모달(owner): 멤버 목록 + 사람 추가 폼" do
    # 기본 로그인 = kim(owner). 시카 작업실엔 최디자(external @ CO0200) 멤버 + 관리 폼.
    page.current_window.resize_to(1440, 900)
    sica = Product.find_by!(name: "시카 수딩 크림")
    visit workspace_path(id: sica.workspace_id)

    assert_text "시카 수딩 크림", wait: 6                       # D2 헤더 작업실명
    assert_selector "button[aria-label='멤버 초대·관리']"

    find("button[aria-label='멤버 초대·관리']").click
    within "dialog[open]" do
      assert_text "최디자"        # 스코프 멤버(모달 멤버 목록)
      assert_text "사람 추가"      # 통합 추가 폼
    end
  end

  test "owner: 제안 목록에서 동료 선택 → 즉시 grant(초대 미생성) → 멤버 목록 반영" do
    # 기본 로그인 = kim(owner). 비타민C 작업실에 최디자(choi — 시카 external, 비타민C엔 비-멤버 addable 후보)를
    # 제안에서 골라 추가하면 재로그인 없이 즉시 workspace-scope grant(초대 미생성).
    page.current_window.resize_to(1440, 900)
    choi = Account.find_by!(email: "choi@partner.example")
    vitc = Product.find_by!(name: "비타민C 브라이트닝 앰플")
    ws = vitc.workspace
    visit workspace_path(ws)
    assert_text "비타민C 브라이트닝 앰플", wait: 6

    find("button[aria-label='멤버 초대·관리']").click
    within "dialog[open]" do
      fill_in "email", with: "choi"                     # 부분일치 → 제안 필터
      find("li[role='option']", text: "최디자").click     # 동료 선택 → 이메일 자동 채움
      find("label", text: "멤버").click                   # contributor — 라디오-카드 피커
      click_button "추가"
    end

    assert_text "작업실 멤버로 추가했습니다", wait: 6          # 즉시 grant 성공 토스트(초대 아님)
    assert RoleAssignment.exists?(account: choi, scope_workspace_id: ws.id),
           "동료 선택 = 이 작업실 workspace-scope grant(즉시)"
    assert_nil Invitation.find_by(email: choi.email), "기존 계정은 초대를 만들지 않는다"

    # 모달 재열기 → 멤버 목록에 최디자 반영.
    find("button[aria-label='멤버 초대·관리']").click
    within("dialog[open]") { assert_text "최디자" }
  end
end
