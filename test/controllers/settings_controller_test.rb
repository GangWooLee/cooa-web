require "test_helper"

# 계정 설정 — 셀프 프로필 편집(accounts 컬럼) · 보안(모든 기기 로그아웃). 기본 로그인=kim@cooa.dev(owner).
class SettingsControllerTest < ActionDispatch::IntegrationTest
  def kim = Account.find_by!(email: "kim@cooa.dev")

  test "show renders the settings page" do
    get settings_path
    assert_response :success
    assert_match "계정 설정", @response.body
    assert_match "프로필", @response.body
    assert_match kim.email, @response.body # 계정 정보(읽기)
  end

  test "update persists profile prefs to the ACCOUNT columns (not the locked users table)" do
    user_name_before = kim.user.name
    patch settings_path, params: { account: { display_name: "쿠아 김", avatar_color: "#2d5a8e", job_title: "ra" } }
    assert_redirected_to settings_path
    acct = kim
    assert_equal "쿠아 김", acct[:display_name]
    assert_equal "#2d5a8e", acct[:avatar_color]
    assert_equal "ra", acct[:job_title]
    # 전역 users(person)는 잠금 — 프로필 편집이 절대 건드리지 않는다.
    assert_equal user_name_before, acct.user.reload.name
    # 표시 해석은 account 우선.
    assert_equal "쿠아 김", acct.name
    assert_equal "#2d5a8e", acct.avatar_color
  end

  test "invalid avatar_color is rejected (422, unchanged)" do
    patch settings_path, params: { account: { avatar_color: "red" } }
    assert_response :unprocessable_entity
    assert_nil kim[:avatar_color]
  end

  test "invalid job_title is rejected (422)" do
    patch settings_path, params: { account: { job_title: "ceo" } }
    assert_response :unprocessable_entity
    assert_nil kim[:job_title]
  end

  test "blank values normalize to nil = 기본값 복귀 (리뷰 F1 원복 경로)" do
    patch settings_path, params: { account: { display_name: "임시", job_title: "ra" } }
    patch settings_path, params: { account: { display_name: "", job_title: "" } }
    assert_redirected_to settings_path
    acct = kim
    assert_nil acct[:display_name]
    assert_nil acct[:job_title]
    assert_equal acct.user.name, acct.name # 폴백 부활
  end

  test "직무 select는 빈 옵션(기본값 사용)을 제공하고 원 컬럼 기준으로 선택된다" do
    get settings_path
    assert_response :success
    assert_match "기본값 사용", @response.body
    # job_title 미설정 상태 → 어떤 실직무 옵션도 selected 아님(첫 옵션 자의 영속 차단).
    assert_no_match(/<option selected[^>]*value="(designer|pm|ra|scm)"/, @response.body)
  end

  test "update never accepts a foreign account id (mass-assignment closed — self only)" do
    other = Account.where.not(email: "kim@cooa.dev").first
    skip "single-account seed" unless other
    patch settings_path, params: { account: { id: other.id, display_name: "탈취" } }
    assert_redirected_to settings_path
    # 내 account만 바뀌고, id는 무시(permit에 없음) → 남의 계정 불변.
    assert_equal "탈취", kim[:display_name]
    refute_equal "탈취", other.reload[:display_name]
  end

  test "sign_out_all bumps token_version and invalidates the current session" do
    before = kim.token_version
    post sign_out_all_path
    assert_redirected_to new_session_path
    assert_equal before + 1, kim.token_version
    # 세션 무효화 → 보호 페이지는 로그인으로 리다이렉트.
    get settings_path
    assert_response :redirect
  end

  test "requires authentication" do
    sign_out
    get settings_path
    assert_response :redirect
  end
end
