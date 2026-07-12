# RLS 쿼리 오버헤드 실측 — owner(BYPASSRLS) vs cooa_app(RLS 술어 적용)

측정일 2026-07-11 · 대상 `cooa_development`(demo:bulk 대량 상태) · 도구 psql 직결 + `EXPLAIN (ANALYZE, BUFFERS, TIMING)` · PostgreSQL 17.7

> 포트폴리오 백로그 #3의 남은 절반. 짝 문서 = `interaction-latency-2026-07.md`(브라우저단 체감). 이 문서는
> **DB 계층에서 RLS 술어가 붙고 안 붙고의 차이**만 본다 — 앱을 전혀 거치지 않는 순수 SQL 계측.

---

## ① 측정 정의 · 공정성 논거

같은 가시 행 집합을 반환하는 동일 쿼리를 **두 연결**로 실행해 planning/execution 시간과 플랜을 비교한다.

| 축 | ① owner 연결 | ② cooa_app 연결 |
|---|---|---|
| 역할 | `igangu`(DB owner, `rolbypassrls = t`) | `cooa_app`(`rolbypassrls = f`) |
| RLS | **미적용**(BYPASSRLS가 정책을 건너뜀) | **적용**(테이블 `FORCE ROW LEVEL SECURITY`) |
| 테넌트 술어 | 쿼리에 **명시** `WHERE tenant_id = '<T>'` | 쿼리에 없음 — 정책이 자동 주입 |
| 실 앱 대응 | 마이그·시드·테스트 스위트 경로 | **런타임 앱 경로**(`database.yml` app_role) |

RLS 정책 술어(`lib/tenant_rls.rb:10-11`):

```sql
tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
```

**공정성 핵심**: owner 쪽에 **명시 `tenant_id = '<T>'` WHERE를 똑같이 줘야** 두 쿼리가 *동일 의미(같은 가시
집합)*가 된다. 그래야 남는 차이가 오직 하나 — owner는 술어가 **상수로 fold**되고, cooa_app은 정책이 주입한
**`current_setting()` 함수 호출**이라는 점 — 로 좁혀진다. owner에 WHERE를 안 주면 "전체 테이블 vs 테넌트
1건"이라는 부당 비교가 되어 RLS 오버헤드가 아니라 술어 유무를 재게 된다.

`<T>` = `TenantConfig::DEMO_TENANT_ID` = `11111111-1111-1111-1111-111111111111`(`config/initializers/tenant_config.rb:9`).

---

## ② 방법 (재현 명령 전문)

### 연결 수립

```bash
# owner (BYPASSRLS) — 명시 WHERE 사용
psql cooa_development -U igangu

# cooa_app (RLS 적용) — 세션 첫 문장에서 GUC 세팅(is_local=false → 세션 스코프,
# 트랜잭션 밖 EXPLAIN 반복에 편함), 이후 WHERE 없이 실행
PGPASSWORD=cooa_dev_pw psql cooa_development -U cooa_app -h localhost
#   → SELECT set_config('app.current_tenant_id','11111111-1111-1111-1111-111111111111', false);
```

역할 성질 확인(측정 전 사전 검증):

```
SELECT current_user, rolbypassrls FROM pg_roles WHERE rolname = current_user;
--  igangu   | t     (owner: RLS 우회)
--  cooa_app | f     (app  : RLS 적용)

-- cooa_app · GUC 미설정 → fail-CLOSED(0행), GUC 설정 → 255행. 정책이 실제로 문지기 역할을 함을 확인.
```

### 계측 프로토콜

각 쿼리를 한 psql 세션 안에서 `EXPLAIN (ANALYZE, BUFFERS, TIMING)`로 **6회 연속** 실행하고,
**1회차(콜드)를 버린 뒤 2–6회차(웜 5회)의 중앙값**을 채택했다. 첫 실행은 카탈로그·플랜·버퍼 캐시가 전부
차가워 압도적으로 느리다(실측: Q2 owner 1회차 planning 1430ms / execution 153ms → 2회차 이후 <1ms). 중앙값은
남은 웜 구간의 산발 스파이크(2회차가 종종 아직 덥혀지는 중)에 견고하다.

3종 쿼리(각 실 앱 쿼리 형태에서 유도):

- **Q1 가시집합 스캔** — 대시보드 제품 목록. owner `SELECT * FROM products WHERE tenant_id='<T>'` vs cooa_app `SELECT * FROM products`.
- **Q2 버전 상세 조인** — `component_versions` 1건 + `annotations` + `annotation_comments`(스레드) LEFT JOIN(버전 상세 뷰가 어노테이션/코멘트를 로드하는 형태). owner는 세 테이블 모두에 `tenant_id='<T>'`를 명시(RLS가 각 스캔에 거는 술어와 대칭).
- **Q3 배지 카운트** — `application_controller.rb:283-287`의 실쿼리: `approval_requests ⋈ approval_request_reviewers`에서 `status='pending' AND reviewer_id=<me>`인 pending 수 + `COUNT(*) FILTER (due_at < now())` overdue를 한 패스에 집계.

샘플 값: `cv.id = 10659`(어노테이션 5·코멘트 6 보유 버전), `reviewer_id = 187`(pending 8건 지정 리뷰어).
재현 SQL 6종은 `/tmp/rls_bench/{q1,q2,q3}_{owner,app}.sql`로 생성해 `psql -f`로 실행했다(세션 스크래치 —
리포에 커밋 안 함).

---

## ③ 환경

| 항목 | 값 |
|---|---|
| PostgreSQL | 17.7 (Homebrew), aarch64-apple-darwin24.6.0 |
| 머신 | Mac15,6 (Apple Silicon) · 11 코어 · 18 GB RAM |
| 서버 설정 | `shared_buffers = 128MB` · `work_mem = 4MB`(둘 다 기본) |
| DB 상태 | `cooa_development`, demo:bulk 대량 |
| 행 수 | products 255 · component_versions 2,521 · annotations 989 · annotation_comments 1,508 · approval_requests 330 · approval_request_reviewers 234 |
| 테넌트 분포 | **전 행 단일 테넌트**(DEMO) — ⑥ 한계 참조 |

**캐비앗**: dev 머신은 측정 중 사용자 작업으로 부하가 들 수 있다. 단발 수치는 신뢰하지 않고 웜 5회 중앙값을
채택한 이유다. 절대값은 프로덕션 레이턴시가 아니라 **동일 조건 두 연결의 상대 비교**로만 읽어야 한다
(EXPLAIN ANALYZE의 노드별 타이밍 계측 오버헤드가 양쪽에 동일하게 얹혀 절대값을 부풀린다).

---

## ④ 결과 (웜 5회 중앙값, ms)

| 쿼리 | owner plan | owner exec | cooa_app plan | cooa_app exec | plan Δ | exec Δ | buffers (owner→app) |
|---|---|---|---|---|---|---|---|
| Q1 products 스캔 | 0.115 | 0.117 | 0.129 | 0.341 | +0.014 (+12%) | +0.224 (+191%) | hit 9 → 9 |
| Q2 버전 상세 조인 | 0.338 | 0.079 | 0.616 | 0.107 | +0.278 (+82%) | +0.028 (+35%) | hit 22 → 21 |
| Q3 배지 카운트 | 0.237 | 0.181 | 0.408 | 0.533 | +0.171 (+72%) | +0.352 (+194%) | hit 24 → 25 |

**플랜 노드 차이(결정적 신호):**

| 쿼리 | owner 플랜 | cooa_app(RLS) 플랜 | 원인 |
|---|---|---|---|
| Q1 | Seq Scan · `Filter: tenant_id = '…'::uuid` | Seq Scan · `Filter: … current_setting() …` | 술어가 전 행 매치(단일 테넌트) → 양쪽 Seq Scan 동일. 상수 → 함수호출만 교체 |
| Q2 | `component_versions`: **Index Only Scan** on `(tenant_id, id)` 유니크 인덱스, Heap Fetches 1 | `component_versions`: **Index Scan** on `pkey(id)` + `Filter: current_setting()` | RLS 술어는 상수가 아니라 인덱스 조건에 못 들어감 → 복합 `(tenant_id,id)` 인덱스 대신 pkey로 후퇴, tenant는 Filter로 강등 |
| Q3 | `approval_request_reviewers`: **Seq Scan** + Filter | `approval_request_reviewers`: **Bitmap Index Scan** on `(tenant_id, reviewer_id)` | 플래너가 `current_setting()` 선택도를 추정 못 함 → 기본 추정으로 인덱스가 유리하다 판단(owner는 상수로 "테넌트가 전 행"임을 알아 Seq Scan 선택) |

원자료(웜 5회 raw, ms) — 중앙값 견고성 확인용:

```
Q1 owner plan 0.630 0.125 0.115 0.089 0.095   exec 2.558 0.117 0.105 0.097 0.204
Q1 app   plan 11.679 0.129 0.101 0.172 0.110  exec 0.439 0.216 0.528 0.213 0.341
Q2 owner plan 1.541 0.476 0.301 0.338 0.302   exec 0.415 0.079 0.063 0.088 0.069
Q2 app   plan 0.451 1.173 0.616 0.469 0.986   exec 0.097 1.241 0.102 0.110 0.107
Q3 owner plan 3.792 0.237 0.316 0.095 0.194   exec 0.500 0.181 0.164 0.117 0.284
Q3 app   plan 0.718 0.298 0.602 0.289 0.408   exec 0.329 0.301 0.533 0.715 0.589
```

---

## ⑤ 해석 (쿼리별 한 줄)

- **Q1** — 실행 +0.22ms(+191%)는 % 만 크지 절대값은 웜 구간 지터(app exec가 5회 중 0.213–0.528ms로 흔들림) 안에 든다. 버퍼는 9→9로 **완전 동일** = RLS가 추가 I/O를 유발하지 않고, 순수 CPU 측 함수 평가 한 번이 얹힐 뿐이다.
- **Q2** — RLS가 복합 `(tenant_id, id)` 인덱스의 Index Only Scan을 무력화하고 pkey Index Scan + Filter로 밀어냈지만, `id`만으로 이미 유니크·고선택도라 버퍼(22→21)·실행시간(0.079→0.107ms) 차이는 사실상 없다. 플랜은 바뀌어도 성능 중립.
- **Q3** — 여기선 RLS 쪽이 오히려 인덱스(Bitmap Index Scan)를 타고 owner가 Seq Scan을 탄다 — 플래너의 `current_setting()` 선택도 추정 실패가 이 작은 테이블에선 **우연히 인덱스 쪽으로** 기울었을 뿐. 실행 +0.35ms 역시 노이즈 수준(app exec 0.301–0.715ms 지터).

**종합**: 이 데이터 규모에서 RLS 술어의 오버헤드는 **미미하다** — 절대 차이는 전부 1ms 미만이고 버퍼(I/O)는
세 쿼리 모두 ±1 이내로 동일하다. planning time이 cooa_app 쪽에서 일관되게 조금 높은 것(모든 문장에 정책 qual이
주입되므로)은 실재하나 역시 1ms 미만이며, prepared statement/제네릭 플랜에서 상각된다. **RLS의 진짜 비용은
"행마다 함수를 부르는 필터"가 아니라 "`current_setting()`이 플래너에게 블랙박스"라는 점** — 상수 fold가 안 돼
① 복합 인덱스 조건에 못 들어가고(Q2) ② 선택도를 못 추정해 플랜 선택이 뒤집힌다(Q3). 지금은 둘 다 성능 중립.

---

## ⑥ 한계

1. **단일 테넌트 데이터**가 가장 큰 한계다. 전 행이 DEMO 테넌트라 테넌트 술어의 선택도가 100%다 — 그래서
   플래너가 `current_setting()` 선택도를 못 봐도 "실제로도 전 행이 대상"이라 손해가 안 난다. **실 멀티테넌트**에서
   한 테넌트가 전체의 1%라면, owner의 상수는 플래너가 정확히 인덱스를 고르게 하지만 RLS의 불투명 함수는 기본
   추정에 의존한다 — 그 방향은 데이터 분포에 따라 유리(Q3식)/불리 어느 쪽으로도 갈리며 이 벤치로는 판정 불가.
2. **작은 테이블·서브밀리초**(255·234행) → Seq Scan이 지배적이고 신호가 노이즈와 같은 자릿수다. 중앙값-5로
   완화했으나 제거하진 못한다. 대량(수십만 행) 테넌트 스캔에서의 인덱스 선택 영향은 별도 측정이 필요하다.
3. **EXPLAIN ANALYZE 계측 오버헤드**가 절대값을 부풀린다(양쪽 동일하게 얹혀 상대 비교는 공정, 절대값은 앱
   레이턴시 아님).
4. **dev 머신·사용자 부하 가능성** → 단발 아닌 중앙값 채택.
5. 이 측정은 SELECT/EXPLAIN 전용(읽기). RLS `WITH CHECK`(INSERT/UPDATE 시점 검증)의 쓰기 경로 오버헤드는
   범위 밖이다.
