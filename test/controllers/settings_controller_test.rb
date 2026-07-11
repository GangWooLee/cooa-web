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
    # 원 컬럼 기준(리졸버 아님) — 개명은 accounts에만 저장되고 users 컬럼은 불변임을 검증하므로 self[:name]을 본다.
    # (User#name은 이제 account-우선 리졸버라 개명 후엔 새 이름을 돌려준다 — F4. 그건 저작권 뷰 일관 반영이 목적이고,
    # 여기 검증 대상인 "users 테이블 잠금"은 원 컬럼으로 봐야 의미가 산다.)
    user_name_before = kim.user[:name]
    patch settings_path, params: { account: { display_name: "쿠아 김", avatar_color: "#2d5a8e", job_title: "ra" } }
    assert_redirected_to settings_path
    acct = kim
    assert_equal "쿠아 김", acct[:display_name]
    assert_equal "#2d5a8e", acct[:avatar_color]
    assert_equal "ra", acct[:job_title]
    # 전역 users(person) 컬럼은 잠금 — 프로필 편집이 절대 건드리지 않는다(원 컬럼으로 확인).
    assert_equal user_name_before, acct.user.reload[:name]
    # 표시 리졸버는 account-우선 — User#name(저작권 뷰 경로)도 개명을 반영한다(F4).
    assert_equal "쿠아 김", acct.user.name
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

  test "아바타 색: raw nil이면 '기본값'(value='') 라디오가 checked이고 리졸브된 폴백 색은 어떤 hex에도 새지 않는다 (리뷰 F1 렌더)" do
    assert_nil kim[:avatar_color] # 시드 기본(폴백 = 리졸버가 #8e0300 반환)
    get settings_path
    assert_response :success
    assert_match %r{<input[^>]*name="account\[avatar_color\]"[^>]*value=""[^>]*checked}, @response.body
    # 리졸브된 폴백(#8e0300)이 hex 라디오에 checked로 굳지 않아야 한다(원 컬럼 기준).
    assert_no_match %r{<input[^>]*value="#8e0300"[^>]*checked}, @response.body
  end

  test "이름만 변경 저장 시 아바타 색 원 컬럼은 nil 유지 (폴백 재영속 방지 — 리뷰 F1 ①)" do
    # 수정된 폼의 기본-체크 라디오(value="")를 그대로 제출 = 이름만 바꾼 저장. 빈 문자열→normalizes로 nil.
    patch settings_path, params: { account: { display_name: "이름만", avatar_color: "" } }
    assert_redirected_to settings_path
    assert_equal "이름만", kim.reload[:display_name]
    assert_nil kim[:avatar_color]
  end

  test "색 선택→저장(raw 영속)→'기본값'(빈값) 재저장→nil 원복 (리뷰 F1 ②)" do
    patch settings_path, params: { account: { avatar_color: "#2f6f6b" } }
    assert_redirected_to settings_path
    assert_equal "#2f6f6b", kim.reload[:avatar_color]
    # 선택한 hex가 원 컬럼 기준으로 checked 렌더.
    get settings_path
    assert_match %r{<input[^>]*value="#2f6f6b"[^>]*checked}, @response.body
    # "기본값"(빈 문자열) 재저장 → nil 정규화 → 폴백 부활.
    patch settings_path, params: { account: { avatar_color: "" } }
    assert_redirected_to settings_path
    assert_nil kim.reload[:avatar_color]
    assert_equal Account::DEFAULT_AVATAR_COLOR, kim.avatar_color # 리졸버 폴백 확인
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
