require "test_helper"

# rack-attack is DISABLED in test by default (Rack::Attack.enabled = !Rails.env.local?) so the rest of the
# request suite — which POSTs /session on every login — is never throttled. Here we flip it ON explicitly
# and reset the MemoryStore counters around each test so throttle state never leaks between tests.
class RackAttackTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear # counters start clean (the parent setup's auto sign-in ran while disabled)
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store.clear
  end

  # login/ip: limit 10 / 20s. account_id: 0 → account not found → 303 redirect (still counts at the middleware,
  # which runs before the controller), so we exercise the throttle without needing valid credentials.
  test "login POST is throttled past the limit with 429 + Retry-After" do
    10.times do
      post session_path, params: { account_id: 0 }
      assert_not_equal 429, response.status, "requests within the limit must pass the throttle"
    end

    post session_path, params: { account_id: 0 }
    assert_equal 429, response.status, "the 11th request in the window must be throttled"
    assert response.headers["Retry-After"].present?, "429 must carry Retry-After"
    assert_operator response.headers["Retry-After"].to_i, :>, 0
  end

  test "requests under the limit are not throttled" do
    9.times do
      post session_path, params: { account_id: 0 }
      assert_not_equal 429, response.status
    end
  end

  # invite/ip: limit 20 / 60s — a higher, independent bucket from login. Confirms rules are per-target.
  test "invitation landing has its own higher throttle bucket" do
    20.times do
      get invite_path("nonexistent-token")
      assert_not_equal 429, response.status
    end

    get invite_path("nonexistent-token")
    assert_equal 429, response.status
    assert response.headers["Retry-After"].present?
  end
end
