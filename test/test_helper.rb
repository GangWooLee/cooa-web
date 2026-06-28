ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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
      org = Organization.find_or_create_by!(name: "COOA Demo") { |o| o.region = "JP" }
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
end
