require "test_helper"

# Flag-absent / tampered pending_signup guard (T3). OnboardingController trusts the IdP `verified` fact
# CARRIED in session[:pending_signup] (SessionsController#start_self_serve_onboarding stamps it) rather than
# assuming it. A signup stash WITHOUT a truthy verified flag — a cookie stale from before the flag existed,
# or a tampered one — is treated as an expired session and bounced to login, never onboarded.
#
# This state is UNREACHABLE via the real callback (the writer always carries verified=true, and an unverified
# identity is rejected before any stash), so it is asserted at the controller (functional) layer, where the
# session can be seeded directly.
class OnboardingControllerTest < ActionController::TestCase
  tests OnboardingController

  test "a pending signup lacking a truthy verified flag bounces to login (no onboarding)" do
    base = { "provider" => "google_oauth2", "subject" => "g-x", "email" => "x@newco.example", "name" => "X" }

    get :new, session: { pending_signup: base } # verified key ABSENT (stale cookie)
    assert_redirected_to new_session_path, "a signup stash without a verified flag is treated as expired"

    get :new, session: { pending_signup: base.merge("verified" => false) } # verified explicitly FALSE
    assert_redirected_to new_session_path, "an explicitly-unverified stash is treated as expired"
  end
end
