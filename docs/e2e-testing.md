# COOA E2E(시스템) 테스트 — 셋업·실행·관리

> 목적: 브라우저 E2E가 **다시는 조용히 죽지 않도록** 셋업·실행·컨벤션을 한곳에. 드라이버 = **Playwright**(capybara-playwright-driver, 2026-07-01 결정 — Selenium 대비 강한 auto-wait로 flakiness↓). Capybara DSL·Rails 시드·Minitest·트랜잭션은 그대로.

## ⚠️ 가장 중요한 교훈 (은폐 방지)
`bin/rails test`는 **시스템(E2E) 테스트를 실행하지 않는다**(Rails 관례). 과거 account-picker 인증 도입 후 E2E 9개가 전부 `/session/new`로 튕겨 **계속 red였는데도** `bin/rails test`만 돌려 **은폐**됐다. → **검증/CI는 반드시 `bin/rails test:system`(또는 `test:all`)까지 돌릴 것.**

| 명령 | 범위 |
|---|---|
| `bin/rails test` | 모델·통합·정책 (**E2E 제외**) |
| `PARALLEL_WORKERS=1 bin/rails test:system` | 브라우저 E2E (`test/system/`) |
| `bin/rails test:all` | 위 **둘 다** — 배포 전 게이트 |

## 셋업 (신규 머신 1회)
```bash
bundle install                       # capybara-playwright-driver + playwright-ruby-client(1.60)
npm install                          # playwright npm — 버전은 package.json에 핀(gem과 정확히 일치해야 함)
npx playwright install chromium      # 브라우저 바이너리(~/Library/Caches/ms-playwright)
```
- **버전핀 필수**: `package.json`의 `playwright`와 Gemfile의 `playwright-ruby-client`는 **정확히 같은 마이너**(현재 **1.60.0**). 드리프트 시 드라이버가 실패한다. caret(`^`) 금지. `package.json`/`package-lock.json`은 커밋(재현성), `node_modules`는 gitignore.
- 드라이버 설정: `test/application_system_test_case.rb`(register `:playwright` chromium headless).

## 인증 (필수 헬퍼)
브라우저 세션은 통합용 `sign_in_as`(= `post session_path`)로 로그인되지 **않는다**. `ApplicationSystemTestCase`가 공통 `setup`에서 시드→**account-picker 실제 클릭**으로 로그인한다:
```ruby
setup { Rails.application.load_seed; system_sign_in("kim@cooa.dev") } # 기본 = owner
# 역할 전환(SoD 등)은 본문에서 재호출: system_sign_in("lee@cooa.dev")
```
`allow_unauthenticated_access(new/create)` 덕에 로그인 중 재호출하면 `create`의 `reset_session`으로 **신원이 전환**된다(리뷰 SoD 라운드트립의 전제).

## 컨벤션 (관리 규칙 — 리서치 기반)
- **소수 고가치 user-journey만**(피라미드/트로피). Pundit 정책·모델·stale은 유닛/통합(152)이 이미 검증 — E2E서 재검증 금지. E2E 목표 = 딥 저니 ~8–15개.
- **`sleep` 금지 → Capybara auto-wait**(`assert_*`/`have_*`, `wait:`). Playwright가 actionability를 자체 대기. (기존 9는 부활 우선이라 일부 `sleep` 잔존 — 신규는 무-sleep.)
- **하드코딩 auto-increment ID 금지**(`f.id`·팩토리로). 시나리오 엔티티(리뷰 대기 버전·작성자≠리뷰어)는 per-test 생성.
- **selector 우선순위**: 사용자가 보는 **텍스트/role** → `data-testid`(무근거 컨테이너 앵커만) → CSS/nth-child 최후. 범용 `within("aside")` 같은 건 id로 구체화(`#app-sidebar`).
- **UX-의도 검증**: 내부 상태가 아니라 **사용자-가시 결과 + 부정 쌍둥이**(권한거부·빈·무효)를 assert. 예: 검토 확인 후 "✓ 검토 확인됨 · 이쿠아" 표시 **그리고** 요청자 본인엔 확인 버튼 **부재**+"(SoD)".
- **DB 확증은 가시 신호 뒤에**: 액션 클릭 직후 `model.reload`는 PATCH/리로드 완료 전 레이스 → 먼저 가시 assertion으로 대기 후 DB 확인.

## 현재 커버리지 (`test/system/`, 12파일·29 테스트 green)
- 기존 9(부활): dashboard/tree CRUD·drawer·sidebar·inline·compare focus·screens(버전 보기/업로드/교체).
- **리프레임 3 저니**(신규):
  - `version_review_test.rb` — 리뷰 요청 → 요청자 본인 확인 불가(SoD) → 리뷰어 확인 / 변경 요청 / contributor 부정.
  - `version_feedback_test.rb` — 단일 버전 뷰 Shift+드래그 피드백(Point 4) / 리뷰어 resolve↔reopen / contributor 부정.

## 저작 보조 (선택)
새 플로우를 organically 발굴할 땐 **Playwright MCP**(AI가 라이브 DOM 탐색)를 저작 보조로 쓰고, 결과를 위 컨벤션의 Capybara 스펙으로 코드화한다. **MCP는 CI 러너가 아니다**(비결정적·고비용). CI 회귀는 항상 이 루비 스펙.
