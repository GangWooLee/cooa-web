require "application_system_test_case"

# Stage 1 E2E: park(contributor)가 리뷰어 미지정으로 리뷰 요청 → lee(approver)가 인박스 Segment B(미배정)에서
# "내가 맡기"로 자기배정 → 행이 Segment A로 이동 → 버전에서 검토 확인. system_sign_in 재호출 = 신원 전환.
class ReviewClaimTest < ApplicationSystemTestCase
  def hero_v5
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: 5)
  end

  test "park 미지정 제출 → lee가 Segment B에서 claim → A로 이동 → 검토 확인" do
    v5 = hero_v5

    # park(contributor): 리뷰어 체크박스 미선택 = 미배정 제출
    system_sign_in("park@cooa.dev")
    visit component_version_path(v5)
    click_button "리뷰 요청"
    assert_text "리뷰 대기"

    # lee(approver): 사이드바 인박스 → Segment B 브랜드 그룹 → "내가 맡기"
    # (사이드바 제품 트리도 <details>·제품코드를 쓰므로 인박스 콘텐츠 확인은 main으로 스코프)
    system_sign_in("lee@cooa.dev")
    click_link "내 리뷰 인박스"
    within "main" do
      assert_text "내가 맡을 수 있는 리뷰"
      assert_selector "details", text: "레티놀 3% 세럼" # 브랜드(루트 제품) 그룹
      within("details", text: "레티놀 3% 세럼") { assert_text "CO0001" }
    end
    click_button "내가 맡기" # main에 유일

    # claim 후: B는 비고(맡을 미배정 없음), CO0001은 A로 이동 → 행에서 버전 진입 후 검토 확인
    within "main" do
      assert_text "맡을 수 있는 미배정 리뷰가 없습니다"
      find("a", text: "CO0001").click
    end
    accept_confirm { click_button "검토 확인" } # v5는 미해결 피드백 → 소프트 경고 수락
    assert_text "검토 확인됨"
  end
end
