# 개발자 온보딩 — 로컬 실행과 규율

새로 합류한 개발자가 앱을 로컬에서 띄우고, 이 저장소의 검증 규율을 익히는 문서다.
제품이 무엇인지는 루트 `README.md`를 먼저 읽는 것이 좋다.

## 유저 저니의 코드 진입점

| 단계 | 컨트롤러와 서비스 |
|---|---|
| 가입, 조직 부트스트랩 | `sessions_controller.rb#omniauth_callback` → `services/organization_bootstrap.rb` |
| 작업실 진입과 생성 | `dashboard_controller.rb#index`, `workspaces_controller.rb` |
| 도안 업로드 | `component_versions_controller.rb#create`, `services/pdf_probe.rb` |
| 스크리닝(룰엔진) | `screenings_controller.rb#run_screening` → `services/screening_service.rb` |
| 검토 요청과 확인 | `approval_requests_controller.rb#create,#confirm`, `services/reviewed_tuple.rb` |
| 감사 기록 | `models/audit_log.rb#record!`, `lib/audit_log_hash.rb` |

## 로컬에서 돌리기

사전 요구: Ruby 3.4.7, PostgreSQL 17, poppler(`pdfinfo` — 업로드 PDF 검증에 쓰이며 없으면 해당 검증은 건너뛴다).

```sh
bin/setup          # 멱등: bundle → git 훅(lefthook) → db:prepare → cooa_app 권한 부여 → bin/dev 기동
bin/setup --reset  # DB를 초기화하고 재구성
bin/dev            # 개발 서버만 (foreman → http://localhost:3000 + tailwind watch)
```

`bin/setup`은 마지막에 `bin/dev`를 실행한다. `--skip-server`로 생략할 수 있다.

## 꼭 알아야 할 함정 (`docs/dev-discipline.md` R1~R9 요약)

- 런타임과 owner 역할이 다르다. 앱은 `cooa_app`(NOBYPASSRLS)로 접속해 RLS가 강제된다.
  마이그레이션, 시드, grant는 owner로 실행한다: `COOA_DB_USER=$USER bin/rails db:migrate`.
  최초 1회 `cooa_app` 역할 생성이 필요하면 `docs/prod-cutover.md` 3절의 SQL을 쓴다.
- 컬럼 마이그레이션 후에는 web을 재시작하고 schema_cache를 다시 덤프한다(R1, R6).
  stale 인메모리 schema_cache는 "테스트는 그린인데 앱은 깨짐"을 만든다.
  `COOA_DB_USER=$USER bin/rails db:schema:cache:dump` 후 커밋.
- `db:migrate db:seed`를 한 줄로 체이닝하지 않는다. 마이그레이션 후 프로세스를 새로 띄운다.
- 새 테이블이나 쓰기 경로를 추가하면 `lib/tasks/cooa.rake`의 grant 그룹에 분류하고
  `rls:grant_app`을 다시 실행한다(R8). 빠뜨리면 `cooa_app`에서 `PG::InsufficientPrivilege` 500이 난다.
- AR 객체를 프로세스나 클래스 레벨에 캐시하지 않는다(R7 — 테넌트 누수와 RLS 우회 위험).

## 테스트와 게이트

```sh
PARALLEL_WORKERS=1 bin/rails test        # 유닛/통합/컨트롤러/모델/폴리시
PARALLEL_WORKERS=1 bin/rails test:all    # 위 + 시스템(Playwright). test:system은 `test`에 포함되지 않는다
bin/smoke                                # DoD: 실앱을 cooa_app으로 부팅해 GET 크리티컬 경로 검증
SMOKE_REQUIRE_WRITE=1 bin/smoke          # 쓰기 왕복까지 (업로드 → 미리보기 → cascade 삭제 → 잔여 0)
bin/ci                                   # 전체 게이트. pre-push 훅이 이것을 실행한다
```

- `PARALLEL_WORKERS=1`은 필수다. macOS에서 parallel fork가 pg 드라이버를 segfault 낸다.
- DoD는 테스트 그린이 아니라 `bin/smoke` 그린과 수동 클릭스루다.

## 더 읽을거리

- `docs/dev-discipline.md` — 검증 규율 R1~R9
- `docs/harness.md` — 어떤 규율이 어디서 기계적으로 강제되는가
- `docs/e2e-testing.md` — Playwright 시스템 테스트
- `docs/error-handling.md` — 에러 표면 규약
- `docs/prod-cutover.md` — 프로덕션 컷오버 런북
