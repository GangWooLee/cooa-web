# 개발 검증 규율 (R1–R7)

> **왜 이 문서가 있나.** 리뷰 리프레임 중, 로컬 dev 서버에서 `ActiveModel::UnknownAttributeError
> (component_version_id)`가 터졌다. 코드 버그가 아니라 **마이그레이션 이전에 부팅된 Puma가 낡은
> in-memory schema cache를 들고 있던 것**이었다. 근본 교훈은 하나다 — **"테스트 그린 ≠ 앱 작동"**.
> 유닛/통합 테스트는 갓 마이그·리시드된 *test* DB를 *test* 환경에서만 검증한다. 사용자가 실제로
> 구동하는 *development* 환경 + *development* DB(영속 캐시·RLS=cooa_app·오래 뜬 프로세스)는
> 재현하지 못한다. 아래 규율은 그 사각지대를 메운다.

---

## R1 — 마이그레이션 후 web 재시작 (필수)

사용 중인 모델의 컬럼을 바꾸는 마이그레이션(추가/삭제/리네임) 뒤에는 **웹 프로세스를 반드시 재시작**한다.
Rails dev 코드 리로드는 열린 DB 커넥션의 `schema_cache`를 비우지 않는다 → 오래 뜬 Puma는 옛 스키마를
계속 믿는다 → `UnknownAttributeError`/`no column` 부류가 런타임에 터진다.

```bash
touch tmp/restart.txt      # Puma phased restart, 또는
# bin/dev 를 Ctrl-C 후 재기동
```

- `db:migrate`와 `db:seed`를 **한 프로세스로 체이닝하지 말 것**(`rails db:migrate db:seed`) — 시드가
  마이그 이전 스키마 캐시로 실행되어 같은 부류로 깨진다. 두 명령을 분리 실행한다.
- 애매하면 재시작한다. 재시작은 싸고, 스파게티 디버깅은 비싸다.

## R2 — 실앱 스모크를 Definition of Done 으로

기능이 "됐다"의 기준은 **테스트 그린이 아니라 `bin/smoke` 그린 + 재시작된 서버에서의 수동 클릭스루**다.
테스트만으로 완료 선언 금지. 최소한:

1. `PARALLEL_WORKERS=1 bin/rails test` + `bin/rails test:system` 그린
2. **`bin/smoke` 그린**(실앱 부팅 → critical path 2xx · 예외 0)
3. 재시작된 dev 서버에서 바뀐 화면을 실제로 클릭

## R3 — `bin/smoke`

실앱(development 환경 · development DB · RLS=cooa_app 경로)을 인프로세스로 부팅해 로그인 후 critical
path를 실제 요청으로 걷는다. 실행 중인 dev 서버와 포트 충돌 없음, 조회(GET)만 해 데이터 무변형.

```bash
bin/smoke                  # development(기본)
SMOKE_ENV=test bin/smoke   # test 환경으로
```

커버: 로그인 페이지 → 로그인 → 대시보드 → 제품 트리 → **버전 리뷰 패널** → 스크리닝 → 리뷰 인박스.
config/routing/initializer/connection/뷰 렌더 실패 등 **유닛이 못 잡는 부팅·통합 결함**을 포착한다.
새 critical path가 생기면 `bin/smoke`에 한 줄 추가한다.

## R4 — strong_migrations (expand-contract)

`strong_migrations`가 unsafe 마이그(컬럼 drop·NOT NULL 즉시 추가·비동시 인덱스 등)를 dev/CI에서
차단하고 안전 대안을 안내한다. 파괴적 변경은 **expand → (배포·백필) → contract** 로 나눈다.
- 이미 검증된 과거 마이그(≤ `20260701000004`)는 `StrongMigrations.start_after`로 검사 제외.
- 불가피하게 안전 규칙을 우회할 땐 이유를 주석으로 남기고 `safety_assured { ... }`로 감싼다(남발 금지).

## R5 — N+1 게이트 (bullet dev · prosopite test)

- **bullet**(development): 뷰 렌더 중 미프리로드 연관을 브라우저 푸터/로그로 즉시 노출. 리뷰 패널·
  제품 트리처럼 연관을 도는 화면을 열 때 프리로드 누락을 바로 알림.
- **prosopite**(test): critical path 통합 테스트를 `assert_no_n_plus_one { ... }`로 감싸면 N+1 감지 시
  raise → 실패. bullet보다 엄격(pluck/loop까지). 새 N+1이 드러나면 그 자리에서 `includes`로 픽스.

## R6 — schema_cache 덤프 커밋

```bash
COOA_DB_USER=$USER bin/rails db:schema:cache:dump   # → db/schema_cache.yml (커밋)
```

부팅 시 Rails가 이 파일로 컬럼/인덱스 메타데이터를 채운다 → dev/prod 부팅 결정적, 첫 요청의
`SHOW FULL FIELDS` 프로브 제거, 워커 부팅 부하 감소. **마이그레이션 후 재덤프**한다(R1과 짝).

## R7 — AR 객체를 프로세스/클래스 수준에 캐시 금지

쿼리 결과(ActiveRecord 객체)를 상수·클래스 변수·프로세스 전역에 캐시하지 않는다 — 요청 간 stale·
테넌트 누수(RLS 우회) 위험. 요청 스코프(`@ivar`)나 명시적 `Rails.cache`(키·TTL 관리)만 사용한다.

---

### 새 기능/수정 체크리스트 (요약)

- [ ] 마이그 후 **web 재시작**(R1) + **schema_cache 재덤프**(R6)
- [ ] `PARALLEL_WORKERS=1 bin/rails test` + `bin/rails test:system` 그린
- [ ] **`bin/smoke` 그린**(R2/R3)
- [ ] critical path에 `assert_no_n_plus_one` 게이트(R5), 새 N+1 0
- [ ] 재시작된 서버에서 수동 클릭스루(R2)
