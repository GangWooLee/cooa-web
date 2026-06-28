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
    # (same "COOA Demo" org as db/seeds) + a Current context, so inline-built records and request
    # paths (Organization.first!) all resolve to ONE tenant — otherwise composite FKs reject the mix.
    setup do
      org = Organization.find_or_create_by!(name: "COOA Demo") { |o| o.region = "JP" }
      Current.tenant_id = org.id
    end

    # Add more helper methods to be used by all tests here...
  end
end
