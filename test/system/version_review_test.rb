require "application_system_test_case"

# 리프레임 E2E — 버전 리뷰(GitHub-PR식 경량 검토, 규제 전자서명 없음). "사용자가 의도대로 경험"을
# 가시적 결과 + 부정 쌍둥이로 검증: 요청자는 본인 리뷰를 확인 못 하고(SoD), 리뷰어만 확인/변경요청.
# 대상 = CO0001/outer_box/v5(JP 스크리닝 시드됨 → 패널이 "리뷰 요청" 상태로 시작).
class VersionReviewTest < ApplicationSystemTestCase
  def hero_v5
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: 5)
  end

  # 핵심 저니: 요청 → 본인 확인 불가(SoD) → 신원 전환 → 리뷰어 확인
  test "리뷰 요청 → 요청자 본인 확인 불가(SoD) → 리뷰어(이쿠아) 검토 확인" do
    v5 = hero_v5
    visit component_version_path(v5) # 김쿠아(owner)=요청자, 부모 setup 로그인

    # 요청 전: 리뷰 요청 버튼 노출(owner는 submit 권한 보유)
    assert_button "리뷰 요청"
    click_button "리뷰 요청"

    # 요청 후: "리뷰 대기" + 요청자 표기 + SoD 게이트(본인엔 확인 버튼 부재 + SoD 문구)
    assert_text "리뷰 대기"
    assert_text "요청자"
    assert_no_button "✓ 검토 확인", wait: 2
    assert_text "본인이 요청한 리뷰는 본인이 확인할 수 없습니다 (SoD)"

    # 리뷰어(이쿠아 approver)로 신원 전환 → 확인 가능 → 확인 → 확정 상태가 사용자에게 보임
    system_sign_in("lee@cooa.dev")
    visit component_version_path(v5)
    assert_button "✓ 검토 확인"
    click_button "✓ 검토 확인"
    assert_text "✓ 검토 확인됨"
    assert_text "이쿠아"
    assert_no_button "✓ 검토 확인", wait: 2 # 확정 후 액션 사라짐(멱등)
  end

  # 변형: 리뷰어가 변경 요청(turbo_confirm 다이얼로그) → 변경요청 상태
  test "리뷰어가 변경 요청" do
    v5 = hero_v5
    visit component_version_path(v5)
    click_button "리뷰 요청"
    assert_text "리뷰 대기"

    system_sign_in("lee@cooa.dev")
    visit component_version_path(v5)
    accept_confirm("이 버전에 변경을 요청하시겠습니까?") { click_button "변경 요청" }
    assert_text "✗ 변경 요청됨"
    assert_text "이쿠아"
  end

  # 부정 페르소나: contributor(박쿠아)는 리뷰어 권한이 없어 확인 버튼 부재
  test "contributor는 검토 확인 버튼 부재(권한 게이팅)" do
    v5 = hero_v5
    visit component_version_path(v5)
    click_button "리뷰 요청"
    assert_text "리뷰 대기"

    system_sign_in("park@cooa.dev") # scm → contributor(리뷰어 아님)
    visit component_version_path(v5)
    assert_text "리뷰 대기"
    assert_no_button "✓ 검토 확인"
  end
end
