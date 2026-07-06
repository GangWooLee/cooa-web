require "test_helper"
require "capybara-playwright-driver"

# E2E 드라이버 = Playwright(capybara-playwright-driver). Selenium 대비 강한 auto-wait로 flakiness↓
# (2026-07-01 결정). Capybara DSL·Rails 시드·Minitest·트랜잭션은 그대로. CLI/브라우저는 로컬 node
# (node_modules/.bin/playwright 1.60 + ms-playwright chromium)에서 해석.
Capybara.register_driver(:playwright) do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :playwright

  # Playwright가 액션마다 actionability를 자체 대기하지만, 무거운 대시보드 렌더용 Capybara 상한도 유지.
  Capybara.default_max_wait_time = 6

  # 모든 시스템 테스트 공통: 시드 → 로그인(순서 중요 — 로그인은 방금 시드된 account를 참조).
  # 기본 신원 = 김쿠아(owner, 전 권한). 역할 전환이 필요한 테스트는 본문에서 system_sign_in 재호출.
  setup do
    Rails.application.load_seed
    system_sign_in("kim@cooa.dev")
  end

  private

  # 브라우저 세션 로그인 = account-picker 실제 클릭. (통합용 sign_in_as[post session_path]는 별도
  # 브라우저 프로세스 세션엔 적용 안 됨.) allow_unauthenticated_access(new/create) 덕에 로그인 상태에서
  # 재호출하면 create의 reset_session으로 신원이 전환됨(SoD 라운드트립 시나리오의 전제).
  def system_sign_in(email)
    visit new_session_path
    # 데모 계정은 Google 우선 위계상 <details>로 접힐 수 있다 — 버튼이 안 보이면 펼친다(의도 보존: 여전히
    # account-picker를 걷는다). test env엔 GOOGLE_CLIENT_ID 미설정 → <details open> 렌더 → 버튼 즉시 가시 →
    # summary 클릭 스킵(무회귀). CI에서 Google이 설정돼도 방어적 open으로 견고.
    find("summary", text: "데모 계정").click unless has_selector?(:button, text: email, wait: 1)
    find("button", text: email).click
    assert_no_current_path new_session_path, wait: 5 # create → root 리다이렉트 완료 대기
  end
end
