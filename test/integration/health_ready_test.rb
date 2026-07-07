require "test_helper"

# /ready deep readiness probe. The happy path (DB up) + body shape are covered here.
#
# The DB-DOWN 503 branch is intentionally NOT simulated: the only seam is making the shared
# ActiveRecord connection's SELECT 1 raise, but that same connection round-trips throughout the request
# pipeline (RLS tenant SET LOCAL, session/account resolution), so stubbing it globally perturbs the request
# before it reaches the controller — an invasive, brittle simulation. The branch is a two-line render guard
# over database_up?'s rescue; its logic is exercised by the private-method contract, not an integration stub.
class HealthReadyTest < ActionDispatch::IntegrationTest
  test "GET /ready returns 200 with db up and the {status, db, queue} body shape" do
    get readiness_check_path
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal %w[db queue status], body.keys.sort
    assert_equal "ok", body["status"]
    assert_equal "up", body["db"]
    # queue infra is not provisioned in the test primary DB → "unavailable"; active/idle are the prod values.
    assert_includes %w[active idle unavailable], body["queue"]
  end

  test "GET /ready is reachable unauthenticated (no login required)" do
    sign_out
    get readiness_check_path
    assert_response :ok
    assert_equal "up", JSON.parse(response.body)["db"]
  end
end
