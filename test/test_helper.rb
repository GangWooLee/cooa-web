ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "prosopite"
require_relative "support/committed_state_cleanup" # shared leak-proof teardown for the NON-transactional RLS suites

# N+1 게이트(R5): scan 블록 안에서 N+1이 감지되면 raise → 테스트 실패. 전역 스캔이 아니라
# assert_no_n_plus_one { ... } 로 critical path에만 옵트인(오탐·픽스처 잡음 회피).
Prosopite.raise = true
Prosopite.rails_logger = false

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Phase 0b: tenant-scoped tables are tenant_id NOT NULL. Ensure THE single demo tenant exists
    # (same "COOA Demo" org as db/seeds) + a Current context, so inline-built records resolve to ONE
    # tenant — otherwise composite FKs reject the mix.
    setup do
      org = Organization.find_or_create_by!(id: TenantConfig::DEMO_TENANT_ID) { |o| o.name = "COOA Demo"; o.region = "JP" }
      Current.tenant_id = org.id
    end
  end
end

# Request tests: Phase 2a-1 removed the fixed auto-login, so every request needs an authenticated
# account. Seed the demo + sign in the operator (김쿠아=owner) by default; identity-specific tests call
# sign_in_as(other) or sign_out. Centralized here — individual request tests no longer call load_seed
# (a per-file reseed would delete the signed-in account and break the session).
class ActionDispatch::IntegrationTest
  setup do
    Rails.application.load_seed
    sign_in_as(Account.find_by!(email: "kim@cooa.dev"))
  end

  def sign_in_as(account)
    post session_path, params: { account_id: account.id }
    account
  end

  def sign_out
    delete session_path
  end

  # critical path의 N+1 게이트. 블록 내 요청이 유사쿼리를 반복하면 Prosopite가 raise → 실패.
  def assert_no_n_plus_one
    Prosopite.scan
    yield
  ensure
    Prosopite.finish
  end
end
