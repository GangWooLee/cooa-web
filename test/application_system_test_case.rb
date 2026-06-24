require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1700, 1050]

  # 무거운 대시보드 뒤 드로어 등에서 Stimulus 연결·풀 리렌더 여유(기본 2초는 부하 시 부족)
  Capybara.default_max_wait_time = 6
end
