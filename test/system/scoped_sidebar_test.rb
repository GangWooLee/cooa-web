require "application_system_test_case"

# Stage 2 (D3): 스코프 계정(최디자 — CO0200 한정 external_collaborator)이 계정 픽커로 로그인하면 제한된
# 트리만 본다 — 부여 제품만, 타 브랜드 루트와 비가시 조상 브랜드는 렌더되지 않음(재루팅). 기본 신원(kim)에서
# system_sign_in 재호출로 choi로 전환.
class ScopedSidebarTest < ApplicationSystemTestCase
  test "스코프 계정은 픽커 로그인 후 부여 제품만 본다" do
    system_sign_in("choi@partner.example")
    page.current_window.resize_to(1440, 900)
    visit root_path
    assert_text "CO0200", wait: 6           # 부여 제품(가시)
    assert_no_text "레티놀 3% 세럼"           # 타 브랜드 루트 — 미렌더
    assert_no_text "비타민C 브라이트닝 앰플"    # 타 브랜드 루트 — 미렌더
    assert_no_text "시카 수딩 크림"           # 비가시 조상 브랜드 — 미렌더(재루팅으로 유출 차단)
  end
end
