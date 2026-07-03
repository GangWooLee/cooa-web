# COOA web — 규율 네비게이션

> 포인터만. 상세는 아래가 진실원천(내용 복제 금지). web/ 에서 세션을 열어도 규율이 발견되도록 존재.

- **개발 검증 규율 R1~R8** — `docs/dev-discipline.md`. DoD = `bin/smoke`(실앱 부팅+쓰기왕복·cooa_app) + `bin/rails test:all`.
- **무엇이 어디서 강제되나(하네스)** — `docs/harness.md`. 게이트: lefthook(pre-commit·commit-msg·pre-push→`bin/ci`) + strong_migrations + P0 Claude 가드. 우회: `--no-verify`.
- **E2E/시스템 테스트** — `docs/e2e-testing.md`. `test:system`은 `bin/rails test`에 없음 → `test:all` (은폐 주의).
- **git 토폴로지 안전 + AI 도구 스택 역할** — 상위 `../CLAUDE.md`(중첩 2-repo · outer를 web-demo로 push 금지).
- **엔지니어링 교훈** — `docs/solutions/`.
