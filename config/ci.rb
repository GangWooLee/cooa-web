# Run using bin/ci
#
# 환경 주의(config/database.yml):
#  · rls:*/audit:* = OWNER 연결 필요 → COOA_DB_USER 오버라이드(기본 $USER). RAILS_ENV 미지정 →
#    development DB(앱이 실제로 도는 cooa_app+RLS 자세 DB) 대상. 카탈로그/체인 조회만(read-only·무변형).
#  · bin/smoke = 반드시 development(기본)로 → cooa_app 연결로 실제 권한 경로. test env는 owner라 은폐.
#  · step 은 system(*argv) — env 접두는 argv로 줘 셸 확장 의존을 피한다.
owner = ENV.fetch("COOA_DB_USER") { ENV.fetch("USER") }

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  # 자세 게이트(이미 abort하나 그동안 수동전용) — owner 연결로 dev DB의 RLS·grant·감사체인 검증.
  step "RLS: tenant posture",      "env", "COOA_DB_USER=#{owner}", "bin/rails", "rls:audit"
  step "RLS: grant posture",       "env", "COOA_DB_USER=#{owner}", "bin/rails", "rls:grant_audit"
  step "Audit: hash-chain verify", "env", "COOA_DB_USER=#{owner}", "bin/rails", "audit:verify"

  # PARALLEL_WORKERS=1 필수 — 병렬 포크 시 pg 드라이버가 macOS fork에서 segfault(COOA 규율·dev-discipline R2).
  step "Tests: Rails", "env PARALLEL_WORKERS=1 bin/rails test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
  step "Tests: System", "env PARALLEL_WORKERS=1 bin/rails test:system"

  # DoD: 실앱 부팅(cooa_app) + 쓰기 왕복(업로드→preview→연쇄삭제·잔여0).
  # SMOKE_REQUIRE_WRITE=1 = 빈 dev DB 거짓통과(쓰기경로 조용히 스킵) 차단.
  step "Smoke: 실앱 부팅+쓰기 왕복", "env", "SMOKE_REQUIRE_WRITE=1", "bin/smoke"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
