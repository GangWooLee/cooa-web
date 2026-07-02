# 인증 provider 등록 (ADR-003 Phase 2b + 2026-07-02 개정).
#  - :google_oauth2 — Google 소셜 로그인 직접 연결(GOOGLE_CLIENT_ID 설정 시). 단일 브로커(Keycloak)는
#    기업 SSO 계약 시점으로 유예(ADR-003 개정 배너 참조). accounts.idp_provider가 provider별
#    subject 네임스페이스를 분리해 향후 브로커 이전 경로를 확보.
#  - :openid_connect — Keycloak OIDC RP(KC_ISSUER 설정 시). 기존 경로 불변·공존.
#  - test 환경은 둘 다 등록(OmniAuth.config.test_mode가 라이브 IdP 없이 콜백 구동).
# 콜백은 provider 무관 단일 seam(sessions#omniauth_callback, routes의 /auth/:provider/callback).
#
# Production fail-fast: local login이 꺼진 prod에서 인증 경로가 하나도 없으면 조용한 전원 락아웃
# 대신 부팅 실패.
google_configured = ENV["GOOGLE_CLIENT_ID"].present?
kc_configured     = ENV["KC_ISSUER"].present?

if Rails.env.production? && !Rails.configuration.x.local_login_enabled && !kc_configured && !google_configured
  raise "인증 경로 없음: GOOGLE_CLIENT_ID(+SECRET) 또는 KC_ISSUER/KC_CLIENT_ID/KC_CLIENT_SECRET/KC_REDIRECT_URI가 production에 필요"
end

if Rails.env.test? || kc_configured || google_configured
  # Local Keycloak (start-dev) serves OIDC discovery over plain HTTP; SWD defaults to HTTPS and would
  # SSL-handshake-fail against it. Allow http discovery ONLY for an http issuer (dev). Prod = https.
  if ENV["KC_ISSUER"].to_s.start_with?("http://")
    require "swd"
    SWD.url_builder = URI::HTTP
  end

  Rails.application.config.middleware.use OmniAuth::Builder do
    if Rails.env.test? || google_configured
      # access_type: online — refresh token을 받지 않음(로그인 신원 확인 용도뿐, 저장 데이터 최소화).
      # prompt: select_account — 다계정 사용자가 매번 계정을 고를 수 있게(팀 온보딩 UX).
      provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"],
               scope: "email,profile", access_type: "online", prompt: "select_account"
    end

    if Rails.env.test? || kc_configured
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
  end
  OmniAuth.config.logger = Rails.logger
end
