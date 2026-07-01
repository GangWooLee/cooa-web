require "application_system_test_case"

# 리프레임 후속 E2E — "내게 요청된 리뷰" 수신함: 지정 리뷰어에게 실제로 도달하고 거기서 확인까지.
# kim이 lee 지정 요청 → lee 로그인 → 사이드바 수신함 → 행 클릭 → 검토 확인. + park(비요청) 빈 수신함.
class ReviewsInboxTest < ApplicationSystemTestCase
  def hero_v5
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: 5)
  end

  test "지정 리뷰어 수신함에서 요청 확인 → 검토 확인 (kim→lee)" do
    v5 = hero_v5
    lee_id = User.find_by!(email: "lee@cooa.dev").id

    # kim(기본 로그인)이 v5를 lee에게 리뷰 요청
    visit component_version_path(v5)
    find("input[type='checkbox'][value='#{lee_id}']").set(true)
    click_button "리뷰 요청"
    assert_text "리뷰 대기"

    # lee로 전환 → 사이드바 "내게 요청된 리뷰" → CO0001 행 → 버전 뷰 → 검토 확인
    system_sign_in("lee@cooa.dev")
    click_link "내게 요청된 리뷰"
    assert_text "내게 요청된 리뷰"
    find("a", text: "CO0001").click
    accept_confirm { click_button "✓ 검토 확인" } # v5는 미해결 피드백 → 소프트 경고 수락
    assert_text "✓ 검토 확인됨"
  end

  test "요청받지 않은 사용자의 수신함은 비어있음 (park)" do
    v5 = hero_v5
    lee_id = User.find_by!(email: "lee@cooa.dev").id
    visit component_version_path(v5)
    find("input[type='checkbox'][value='#{lee_id}']").set(true)
    click_button "리뷰 요청"

    system_sign_in("park@cooa.dev") # contributor, 비요청
    click_link "내게 요청된 리뷰"
    assert_text "요청된 리뷰가 없습니다"
  end
end
