# OIDC RP for Keycloak (ADR-003 Phase 2b). Registered only when configured (KC_ISSUER present) or in
# test (so OmniAuth.config.test_mode can drive the callback without a live Keycloak). `discovery: true`
# pulls endpoints + JWKS from issuer/.well-known LAZILY (first request) → no network at boot. The login
# button is shown only when KC_ISSUER is set, so dev-without-Keycloak never hits the request phase.
#
# Production fail-fast: local login is disabled in prod (config.x.local_login_enabled = !production), so
# the OIDC broker MUST be configured — boot rather than silently lock everyone out.
if Rails.env.production? && !Rails.configuration.x.local_login_enabled && ENV["KC_ISSUER"].blank?
  raise "KC_ISSUER/KC_CLIENT_ID/KC_CLIENT_SECRET/KC_REDIRECT_URI required in production (no OIDC broker)"
end

if Rails.env.test? || ENV["KC_ISSUER"].present?
  # Local Keycloak (start-dev) serves OIDC discovery over plain HTTP; SWD defaults to HTTPS and would
  # SSL-handshake-fail against it. Allow http discovery ONLY for an http issuer (dev). Prod = https.
  if ENV["KC_ISSUER"].to_s.start_with?("http://")
    require "swd"
    SWD.url_builder = URI::HTTP
  end

  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :openid_connect,
             discovery: true,                       # endpoints + JWKS from issuer/.well-known (lazy)
             scope: %i[openid profile email],
             response_type: :code,                  # authorization code flow
             pkce: true,                            # PKCE S256 (defense-in-depth for confidential client)
             uid_field: "sub",                      # stable IdP subject → Account.idp_subject
             issuer: ENV.fetch("KC_ISSUER", "http://oidc.test/realms/cooa"), # test = dummy (test_mode bypasses)
             client_options: {
               identifier: ENV["KC_CLIENT_ID"],
               secret: ENV["KC_CLIENT_SECRET"],
               redirect_uri: ENV["KC_REDIRECT_URI"]
             }
  end
  OmniAuth.config.logger = Rails.logger
end
