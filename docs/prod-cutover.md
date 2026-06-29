# COOA 웹앱 — 프로덕션 컷오버 런북 (Phase 0~3)

데모(로컬 account-picker · 단일 Postgres 역할 · 정적 데이터)에서 **프로덕션**으로 넘어갈 때의 단계. Phase 0~3에서 구축한 보안 토대를 실제로 강제하는 설정·시퀀스를 정리한다.

> 코드 진실원천: `config/database.yml`(app_role seam) · `config/initializers/{tenant_config,omniauth}.rb` · `config/application.rb`(`config.x.local_login_enabled`) · `lib/tasks/cooa.rake`(`rls:grant_app`/`rls:audit`) · `lib/tasks/audit.rake`(`audit:verify`).

---

## 1. 무엇이 프로덕션에서 강제되나
- **테넌트 격리(RLS)**: 앱이 `cooa_app`(NOSUPERUSER·NOBYPASSRLS)로 접속 → 17개 테넌트 테이블의 RLS policy(`tenant_id = current_setting('app.current_tenant_id')`, fail-CLOSED)가 실집행.
- **인증**: 로컬 picker **비활성**(prod), **Keycloak OIDC 전용**. 미연계 시 부팅 fail-fast.
- **인가**: Pundit(`verify_authorized` strict), 신원 SoD(승인자≠제출자).
- **감사**: `audit_logs` append-only(grant + 불변 트리거) 해시체인. deny/승인 전이 기록.

---

## 2. 선행 조건
- **PostgreSQL** 17.x (+ `pgcrypto`). DDL용 **owner/migrator** 역할 + 런타임용 **`cooa_app`** 역할.
- **Keycloak**(프로덕션 모드 — TLS·영속 DB; `start-dev` 아님). realm + confidential client.
- **시크릿 매니저**: `SECRET_KEY_BASE`/`RAILS_MASTER_KEY`, `COOA_APP_PASSWORD`(cooa_app DB 비번), `KC_CLIENT_SECRET`. **리포에 커밋 금지**(dev realm JSON의 인라인 secret은 로컬 전용).

---

## 3. DB 역할 (수동 생성 — 마이그/rake는 GRANT만 함)
```sql
-- 런타임 앱 역할 (DDL 불가, RLS 우회 불가)
CREATE ROLE cooa_app LOGIN PASSWORD '<COOA_APP_PASSWORD>'
  NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
-- 마이그/시드/grant는 테이블 소유자(또는 별도 cooa_migrator)로 수행.
```
> `cooa_app`이 **반드시 NOBYPASSRLS**여야 RLS가 의미를 가짐(`rls:audit`가 검증). dev 기본 비번 `cooa_dev_pw`는 prod 사용 금지.

---

## 4. 환경변수
| 변수 | 런타임(앱=cooa_app) | 마이그/시드/grant(owner) |
|---|---|---|
| `COOA_DB_USER` | **미설정** → app_role(cooa_app) | **owner**로 설정(override가 이김) |
| `COOA_APP_USER` | `cooa_app`(기본) | — |
| `COOA_APP_PASSWORD` | **시크릿**(필수) | — |
| `COOA_DB_PASSWORD` | — | owner 비번(필요 시) |
| `COOA_TENANT_ID` | **필수**(SI silo 루트 org uuid; `TenantConfig`가 prod에서 blank면 raise) | 동일 |
| `KC_ISSUER` | `https://<keycloak>/realms/<realm>`(필수) | — |
| `KC_CLIENT_ID` | `cooa-rails` | — |
| `KC_CLIENT_SECRET` | **시크릿**(필수) | — |
| `KC_REDIRECT_URI` | `https://<app>/auth/openid_connect/callback` | — |
| `SECRET_KEY_BASE` | **시크릿**(세션 암호화) | — |
| `RAILS_ENV` | `production` | `production` |

핵심 seam(`database.yml`): **`COOA_DB_USER`가 설정되면 그 값(owner)으로, 미설정이면 `cooa_app`으로** 접속. 따라서 **마이그/시드/grant 명령에만 `COOA_DB_USER=<owner>`를 붙이고, 앱 프로세스에는 붙이지 않는다.**

---

## 5. 로컬 로그인 OFF · OIDC 전용 (자동)
- `config.x.local_login_enabled = !Rails.env.production?` → prod=false → account-picker 라우트 404(`SessionsController#ensure_local_login_enabled`).
- `config/initializers/omniauth.rb`: prod + local_login off + `KC_ISSUER` blank → **부팅 raise**(OIDC 미설정 시 전원 잠김 방지). `KC_ISSUER`가 https면 정상 discovery(dev 전용 SWD http 우회는 http 이슈어에만 적용 → prod 무관).

---

## 6. Keycloak (프로덕션)
- 프로덕션 모드(`start`, TLS, 영속 DB). dev `docker-compose.keycloak.yml`/`realm-cooa.json`은 **로컬 검증 전용**(참조 템플릿).
- realm + confidential client `cooa-rails`: standard flow, **PKCE S256**, `redirectUris`=prod 콜백, web origin=prod. client secret은 **시크릿 매니저**(realm export는 secret 미포함 — kcadm/REST로 주입).
- 사용자 매핑: 최초 OIDC 로그인이 **email로 기존 Account에 link + idp_subject 바인딩**(현 데모 정책). prod 온보딩은 **invitation 게이트**(ADR-002 §6 — Phase 3+에서 정식화; 현재는 email-link).
- **연결→테넌트는 토큰 org claim을 신뢰하지 않음** — `COOA_TENANT_ID`(연결 상수)로만 해석(ADR-003 §2.1).

---

## 7. 배포 시퀀스 (릴리스마다)
모두 **owner**로 1~4, 앱은 cooa_app:
1. `COOA_DB_USER=<owner> RAILS_ENV=production bin/rails db:prepare` — 스키마 로드/마이그(structure.sql가 RLS policy + audit 불변 트리거 보존; **GRANT는 strip됨**).
2. `COOA_DB_USER=<owner> RAILS_ENV=production bin/rails rls:grant_app` — cooa_app 권한 재적용(RLS 테이블 DML · read-only SELECT · **audit_logs SELECT/INSERT만** · 시퀀스 USAGE). **스키마 로드 후 매번 필수**.
3. `COOA_DB_USER=<owner> RAILS_ENV=production bin/rails rls:audit` — **배포 게이트**: 테넌트 테이블 RLS 누락 또는 cooa_app의 audit_logs UPDATE/DELETE 권한 있으면 abort.
4. (최초/온보딩) prod org를 `COOA_TENANT_ID`로 생성 + 계정/role_assignment 프로비저닝. **데모 시드(db/seed) 사용 금지**(데모 데이터).
5. 앱 기동(`COOA_DB_USER` 미설정 → cooa_app) → RLS end-to-end 강제.

마이그레이션은 항상 `COOA_DB_USER=<owner> bin/rails db:migrate` 후 **2의 grant 재실행**. cooa_app으로 마이그 금지(DDL 불가).

---

## 8. 컷오버 후 검증 (prod 스모크)
- `rls:audit` green(17 테넌트 + append-only 가드).
- cooa_app: 로그인 계정 조회·대시보드 SELECT·도메인 INSERT 가능 / `audit_logs` UPDATE·DELETE **거부**.
- OIDC: `<KC_ISSUER>/.well-known/openid-configuration` 200 → 브라우저 로그인 → 콜백 → 대시보드.
- `audit:verify` 체인 무결.
- 로컬 picker 라우트(`/session/new`) **404**(prod).

---

## 9. 전송·세션 하드닝
- `config.force_ssl = true`(production.rb 확인) → Secure 쿠키·HSTS. 리버스 프록시면 `config.assume_ssl`.
- `SECRET_KEY_BASE` 시크릿. 세션 쿠키 httpOnly/SameSite(Rails 기본) 확인.
- revocation: 매요청 `token_version`/status 재검사(suspend/deprovision/역할변경 시 `Account#bump_token_version!`) — 코드 내장. idle timeout 60분.

---

## 10. 롤백
- 직전 릴리스로 되돌림. owner/cooa_app 분리·grant는 **멱등**(`rls:grant_app` 재실행 가능). 스키마 다운마이그는 신중(RLS/트리거 포함).
- 긴급 시 dev처럼 owner로 앱 기동(`COOA_DB_USER=<owner>`)은 **RLS 우회**가 되므로 prod 금지(진단 한정).

---

## 11. 연기/오픈 항목 (ADR §13)
- 멀티테넌트 SaaS의 host→tenant 해석(현재는 SI silo `COOA_TENANT_ID` 상수).
- invitation 기반 JIT 프로비저닝(현 email-link)·MFA step-up·승인 위임·다시장 roll-up.
- `audit_logs` 보존/아카이브 정책(7년 무결).
- vestigial `screening_runs` 승인 컬럼(status/approved_by_id/approved_at) 드롭 마이그.
- AI-엔진 데이터 인프라(Qdrant/OpenSearch/BGE-M3)는 **별개 트랙**(이 런북 범위 밖).

---

## 12. 운영 SOP (P4 — 스케일/운영 검증)
**키 로테이션 (3개 시크릿)**
- `COOA_APP_PASSWORD`(cooa_app): `ALTER ROLE cooa_app PASSWORD '<new>'` → 시크릿 매니저 갱신 → 앱 롤링 재시작. (미설정 시 prod는 부팅 fail-fast — `database.yml`)
- `KC_CLIENT_SECRET`: Keycloak에서 client secret 재발급(kcadm/REST) → 시크릿 갱신 → 재시작.
- `SECRET_KEY_BASE`: ⚠️ 로테이션 시 **세션 쿠키 암호화 키가 바뀌어 전 세션 무효화**(강제 전체 로그아웃). 무중단 필요 시 `secret_key_base` rotations 설정 후 단계적 폐기.

**커넥션 풀링**
- `TenantContext.with_tenant`는 `set_config(...,true)`=**SET LOCAL**(트랜잭션 경계) → **PgBouncer 트랜잭션 풀링 모드 지원**(session 풀링 불필요; 세션 레벨 SET/prepared state 없음). 풀드 컷오버 시 transaction pooling 사용.

**백업/복원 vs 해시체인**
- domain+audit 정합을 위해 **단일 일관 스냅샷**(PITR 또는 단일 트랜잭션 덤프) 강제. 부분 백업 혼합 금지.
- `audit:verify`는 **tail 절단(최근 이력 유실)을 못 잡음**(1..N 연속이면 PASS) — 복원 후 최신 `tenant_seq`를 외부 기록과 대조.

**모니터링**
- `audit:detect_bola`(deny 급증=BOLA 신호)를 야간 recurring으로 등록(`config/recurring.yml`). 알림 싱크 연동은 2b.
- 배포 게이트 `rls:audit`/`audit:verify`를 **체크인된 배포 스크립트**로 고정(사람 누락 방지; 2b에 블로킹 CI로 승격).

## 13. 2b 스케일 게이트 (트리거 명시 — 2a에선 손대지 말 것)
- **audit_logs RANGE 파티셔닝(by `ts`) + DROP 아카이빙** — 불변 트리거가 DELETE 차단 → DROP만이 purge 경로. 트리거: 풀드 전환 OR 단일테이블 >~1천만 행.
- **요청-수명 트랜잭션 풀 점유** — `scope_to_tenant`가 액션+렌더 전체를 1 tx로 핀. 트리거: 2b 부하테스트서 connection 고갈 관측.
- **`detect_bola` 알림 채널** + **`rls:audit`/`audit:verify` 블로킹 CI 스텝** — 트리거: 풀드 SaaS 출시 전.
- **advisory lock 32-bit 충돌**(`hashtext(uuid)`) — 트리거: 테넌트 수천 도달(정확성은 `UNIQUE(tenant,seq)`가 보증, throughput만).
- **dashboard `tree_preorder` N+1**(루트만 preload) — 트리거: 대형 제품트리. flat 로드+Ruby 그룹핑으로 O(1) 쿼리화.
- **`users` 테이블 tenant_id+RLS**(2a RLS-면제) — 트리거: pooled 멀티테넌트(freeze spec §5).
- **인덱스**: `idx_ra_eligible_approver`(P4 ②)는 이미 추가(2a 무영향·2b 헤지). silo의 0-선택도 `tenant_id` 인덱스는 2b 풀드에서 발효.
