# 소셜 로그인 셋업 도우미 — Google Cloud Console 셋업 전후의 마찰 제거(dev 전용 보조).
# 실 OAuth 왕복은 외부 IdP라 자동화 불가 — 이 태스크들은 그 수동 검증을 쉽게 만든다.
namespace :auth do
  REDIRECT_URI = "http://localhost:3000/auth/google_oauth2/callback".freeze
  SEED_OWNER   = "kim@cooa.dev".freeze # 시드 owner(김쿠아) — 직접 로그인 테스트 기준 계정

  desc "Google 소셜 로그인 앱-측 준비 확인 + 콘솔에 넣을 리디렉션 URI 출력(전 환경 안전·읽기전용)"
  task google_preflight: :environment do
    id  = ENV["GOOGLE_CLIENT_ID"].presence
    sec = ENV["GOOGLE_CLIENT_SECRET"].presence
    provider_registered = OmniAuth.strategies.any? { |s| s.default_options[:name].to_s == "google_oauth2" } ||
                          (defined?(OmniAuth::Strategies::GoogleOauth2))

    puts "── Google 소셜 로그인 preflight ──"
    puts "GOOGLE_CLIENT_ID     : #{id ? "설정됨 (…#{id[-6..] || id})" : "미설정 ✗"}"
    puts "GOOGLE_CLIENT_SECRET : #{sec ? "설정됨" : "미설정 ✗"}"
    puts "omniauth-google-oauth2 gem : #{provider_registered ? "로드됨" : "미로드 ✗"}"
    puts
    puts "Google Cloud Console에 넣을 값:"
    puts "  · OAuth 동의 화면: External · scope = email, profile, openid"
    puts "  · 승인된 리디렉션 URI (정확히): #{REDIRECT_URI}"
    puts
    if id && sec
      puts "✓ 앱 측 준비 완료 — bin/dev 재기동 후 로그인 페이지에 'Google로 로그인' 버튼이 뜹니다."
      puts "  다음: 초대 플로우(콘솔 0)로 검증하거나, 직접 로그인은 `bin/rails auth:link_google[<본인@gmail>]` 후 시도."
    else
      puts "✗ env 미설정 — 셸에서 export 후 bin/dev 재기동:"
      puts "    export GOOGLE_CLIENT_ID=<client-id>"
      puts "    export GOOGLE_CLIENT_SECRET=<client-secret>"
    end
  end

  desc "[dev 전용] 직접 로그인 테스트용 — 시드 owner(kim) 이메일을 내 Gmail로 정렬. 예: auth:link_google[me@gmail.com]"
  task :link_google, [ :email ] => :environment do |_t, args|
    abort "dev 전용 태스크입니다 (현재 #{Rails.env})" unless Rails.env.development?
    email = args[:email].to_s.strip.downcase
    abort "이메일 인자 필요 — 예: bin/rails auth:link_google[me@gmail.com]" if email.blank?

    TenantContext.with_tenant(TenantConfig.connection_tenant_id) do
      acc = Account.find_by(email: SEED_OWNER) || Account.joins(:user).find_by(users: { email: SEED_OWNER })
      abort "시드 owner 계정(#{SEED_OWNER})을 찾지 못함 — db:seed 했나요?" if acc.nil?
      original = acc.email
      acc.update!(email: email, idp_provider: nil, idp_subject: nil) # 미바인딩 상태로 정렬(첫 로그인이 바인딩)
      puts "✓ owner 계정 이메일을 #{email}로 정렬(원본: #{original})."
      puts "  이제 이 Gmail로 'Google로 로그인' → 대시보드 진입(owner 권한). email_verified 필수."
      puts "  되돌리기: bin/rails auth:unlink_google"
    end
  end

  desc "[dev 전용] link_google 원복 — owner 계정을 시드 이메일(#{SEED_OWNER})로 복원 + 바인딩 초기화"
  task unlink_google: :environment do
    abort "dev 전용 태스크입니다 (현재 #{Rails.env})" unless Rails.env.development?
    TenantContext.with_tenant(TenantConfig.connection_tenant_id) do
      # user.email(불변 시드 도메인 person)로 owner Account를 되찾아 복원.
      acc = Account.joins(:user).find_by(users: { email: SEED_OWNER })
      abort "owner 계정을 찾지 못함(user #{SEED_OWNER})" if acc.nil?
      acc.update!(email: SEED_OWNER, idp_provider: nil, idp_subject: nil)
      puts "✓ owner 계정을 #{SEED_OWNER}로 복원 + IdP 바인딩 초기화."
    end
  end
end
