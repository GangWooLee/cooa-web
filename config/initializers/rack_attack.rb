# Rate limiting (rack-attack) — throttles the PRE-AUTH credential + provisioning surface so a single IP
# cannot brute-force the account picker / OAuth callback or hammer self-serve onboarding and invite landing.
# The middleware is auto-inserted by rack-attack's Railtie; this file only configures store, gate, and rules.
#
# ENABLED: production only. dev/test run with Rack::Attack.enabled = false so local flows and the request
# suite (which POSTs /session on every login) are never throttled; the rack_attack test flips it on explicitly.
#
# STORE: per-process MemoryStore — sufficient for the initial SINGLE-PROCESS / single-node deployment.
# ⚠️ MULTI-PROCESS or MULTI-HOST: replace with a SHARED store (Redis via ActiveSupport::Cache::RedisCacheStore)
# or every worker keeps its own counter and the effective limit multiplies by the worker count.
Rack::Attack.enabled = !Rails.env.local?
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Pre-auth surface paths (routes measured 2026-07-07 against config/routes.rb).
module CooaRackAttack
  LOGIN_PATH      = "/session"               # POST — dev/test account-picker create (SessionsController#create)
  ORG_SELECT_PATH = "/session/organization"  # POST — same-identity multi-org picker (#select_organization)
  ONBOARDING_PATH = "/onboarding"            # POST — self-serve org bootstrap (OnboardingController#create)
  # GET|POST — OIDC/OAuth callback. Invitation ACCEPTANCE has no dedicated POST route: acceptance converges
  # on this callback (social login → SessionsController#omniauth_callback → accept_invitation_signup), so
  # throttling the callback also covers the accept path.
  CALLBACK_RE     = %r{\A/auth/[^/]+/callback\z}
  INVITE_RE       = %r{\A/invite/[^/]+\z}    # GET — invitation landing (raw token in path; enumeration guard)
end

# Login attempts (account-picker create). 10 / 20s / IP.
Rack::Attack.throttle("login/ip", limit: 10, period: 20.seconds) do |req|
  req.ip if req.post? && req.path == CooaRackAttack::LOGIN_PATH
end

# Org selection POST (multi-org identity). 10 / 20s / IP.
Rack::Attack.throttle("org_select/ip", limit: 10, period: 20.seconds) do |req|
  req.ip if req.post? && req.path == CooaRackAttack::ORG_SELECT_PATH
end

# OAuth/OIDC callback (also the invitation-accept convergence). 15 / 60s / IP.
Rack::Attack.throttle("auth_callback/ip", limit: 15, period: 60.seconds) do |req|
  req.ip if CooaRackAttack::CALLBACK_RE.match?(req.path)
end

# Self-serve onboarding create (org bootstrap — expensive, minted rarely). 5 / 60s / IP.
Rack::Attack.throttle("onboarding/ip", limit: 5, period: 60.seconds) do |req|
  req.ip if req.post? && req.path == CooaRackAttack::ONBOARDING_PATH
end

# Invitation landing (token enumeration guard). 20 / 60s / IP.
Rack::Attack.throttle("invite/ip", limit: 20, period: 60.seconds) do |req|
  req.ip if req.get? && CooaRackAttack::INVITE_RE.match?(req.path)
end

# 429 responder — JSON body + Retry-After (seconds until the current fixed window rolls over). rack-attack
# exposes the matched throttle window in rack.attack.match_data (:period, :epoch_time).
Rack::Attack.throttled_responder = lambda do |req|
  md = req.env["rack.attack.match_data"] || {}
  period = md[:period].to_i
  now = (md[:epoch_time] || Time.now.to_i).to_i
  retry_after = period.positive? ? (period - (now % period)) : 60
  headers = {
    "Content-Type" => "application/json",
    "Retry-After" => retry_after.to_s
  }
  [ 429, headers, [ { error: "요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요." }.to_json ] ]
end
