require "application_system_test_case"

# W1/W2 스코프 격리(D3): 스코프 계정(최디자 — CO0200 한정 external_collaborator)은 홈에 자기 작업실 카드만
# 보고, 진입하면 사이드바 컨텍스트 트리도 자기 작업실만 렌더한다 — 타 작업실 카드/트리와 비가시 조상 브랜드는
# 렌더되지 않음(재루팅). 기본 신원(kim)에서 system_sign_in 재호출로 choi로 전환.
class ScopedSidebarTest < ApplicationSystemTestCase
  test "스코프 계정은 홈에 자기 작업실 카드만·진입 후 사이드바도 자기 트리만" do
    system_sign_in("choi@partner.example")
    page.current_window.resize_to(1440, 900)
    co0200 = Product.find_by!(code: "CO0200")

    # 홈 = 작업실 카드. 자기 작업실(CO0200=미국)만, 타 작업실 카드/조상 브랜드 부재. 리프 스코프라 카드
    # 라벨은 볼 수 있는 표시 루트명(미국) — 조상 작업실명은 클립(유출 차단).
    visit root_path
    assert_text "미국", wait: 6              # 부여 제품 카드(볼 수 있는 표시 루트명)
    assert_no_text "레티놀 3% 세럼"           # 타 작업실 카드 — 미렌더
    assert_no_text "비타민C 브라이트닝 앰플"    # 타 작업실 카드 — 미렌더
    assert_no_text "시카 수딩 크림"           # 비가시 조상 브랜드 — 미렌더(재루팅으로 유출 차단)

    # 진입 → 사이드바 컨텍스트 트리 = 자기 작업실 서브트리만.
    visit workspace_path(co0200.derived_workspace)
    within "#app-sidebar" do
      assert_text "CO0200", wait: 6          # 자기 트리(재루팅된 리프)
      assert_no_text "레티놀 3% 세럼"
      assert_no_text "비타민C 브라이트닝 앰플"
      assert_no_text "시카 수딩 크림"
    end
  end
end
