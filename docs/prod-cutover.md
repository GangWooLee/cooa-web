# COOA 웹앱 — 프로덕션 컷오버 런북 (Phase 0~3)

> ## ⚠️ [2026-07-01 v0.4 리프레임 — step-up/AR_ENCRYPTION 항목 폐기]
> 규제 전자서명(B2 step-up TOTP·Part-11)이 제거됨(경량 "버전 리뷰"로 재구성). 따라서 이 런북의 **`AR_ENCRYPTION_PRIMARY_KEY`·`AR_ENCRYPTION_DETERMINISTIC_KEY`·`AR_ENCRYPTION_KEY_DERIVATION_SALT` 3개 부팅 시크릿·`/step-up` 등록·AR 라운드트립/step-up e2e 스모크·AR 키 로테이션/롤백 항목은 모두 불필요**(해당 코드·initializer·컬럼 삭제됨, 마이그 `20260701000001`). 시크릿은 `SECRET_KEY_BASE`/`RAILS_MASTER_KEY`·`COOA_APP_PASSWORD`·`KC_*`만 유지. 나머지(RLS·cooa_app·OIDC·force_ssl·seed prod 가드)는 불변.

> ## ⚠️ [2026-07-06 정정 — 신원 기반 테넌트 해석 전환 + AR/step-up 사문(死文) 확정]
> 두 가지 stale 정정(코드 대조 완료):
> 1. **테넌트 해석 = 세션 신원 기반**(IT-트랙). `Current.tenant_id`는 더 이상 연결 상수(`COOA_TENANT_ID`)가 아니라 **로그인 세션의 `session[:tenant_id]`**(신원검증 후 저장)에서 온다(`authentication.rb:47-48`). 로그인 전 발견은 **`auth_lookup_*` SECURITY DEFINER 브리지 함수**가 담당(마이그 `20260706000001`). 아래 §6/§7의 "SI-silo COOA_TENANT_ID 상수" 서술은 단일 배포·단일 org 시나리오에 한해 유효하며, 다조직 셀프서브에선 §3의 **BYPASSRLS 게이트**가 컷오버 필수. `COOA_TENANT_ID`는 데모/단일-org 폴백으로만 잔존.
> 2. **AR_ENCRYPTION_*·`/step-up`은 사문**. 상단 v0.4 배너대로 코드·initializer·컬럼 삭제됨(`config/initializers/active_record_encryption.rb` 부재 확인). 본문 §2·§4·§7-4·§8·§9·§10·§12에 남은 AR_ENCRYPTION/step-up 언급은 **전부 역사적 사문 — 프로비저닝·스모크·로테이션에서 무시하라**. 필요 시크릿은 `SECRET_KEY_BASE`/`RAILS_MASTER_KEY`·`COOA_APP_PASSWORD`·`GOOGLE_CLIENT_*`(·KC 사용 시 `KC_*`)뿐.
> 준비도 전반은 vault `REF-프로덕션-준비도-지도.md`(2026-07-06 6축 감사) 참조 — 이 런북=how, 그 지도=what/상태.

데모(로컬 account-picker · 단일 Postgres 역할 · 정적 데이터)에서 **프로덕션**으로 넘어갈 때의 단계. Phase 0~3에서 구축한 보안 토대를 실제로 강제하는 설정·시퀀스를 정리한다.

> 코드 진실원천: `config/database.yml`(app_role seam) · `config/initializers/{tenant_config,omniauth}.rb` · `config/application.rb`(`config.x.local_login_enabled`) · `lib/tasks/cooa.rake`(`rls:grant_app`/`rls:audit`) · `lib/tasks/audit.rake`(`audit:verify`).

---

## 1. 무엇이 프로덕션에서 강제되나
- **테넌트 격리(RLS)**: 앱이 `cooa_app`(NOSUPERUSER·NOBYPASSRLS)로 접속 → 20개 테이블(테넌트 DML 19 + append-only 감사 로그)의 RLS policy(`tenant_id = current_setting('app.current_tenant_id')`, fail-CLOSED)가 실집행.
- **인증**: 로컬 picker **비활성**(prod), **Keycloak OIDC 전용**. 미연계 시 부팅 fail-fast.
- **인가**: Pundit(`verify_authorized` strict), 신원 SoD(승인자≠제출자).
- **감사**: `audit_logs` append-only(grant + 불변 트리거) 해시체인. deny/승인 전이 기록.

---

## 2. 선행 조건
- **PostgreSQL** 17.x (+ `pgcrypto`). DDL용 **owner/migrator** 역할 + 런타임용 **`cooa_app`** 역할.
- **Keycloak**(프로덕션 모드 — TLS·영속 DB; `start-dev` 아님). realm + confidential client.
- **시크릿 매니저**: `SECRET_KEY_BASE`/`RAILS_MASTER_KEY`, `COOA_APP_PASSWORD`(cooa_app DB 비번), `KC_CLIENT_SECRET`, **`AR_ENCRYPTION_PRIMARY_KEY`·`AR_ENCRYPTION_DETERMINISTIC_KEY`·`AR_ENCRYPTION_KEY_DERIVATION_SALT`**(B2 step-up `accounts.totp_secret` 암호화 — **영구 시크릿·재생성 금지**: 재생성/유실 시 전 결재자 totp_secret 복호화 불가). **리포에 커밋 금지**(dev realm JSON의 인라인 secret은 로컬 전용).

---

## 3. DB 역할 (수동 생성 — 마이그/rake는 GRANT만 함)
```sql
-- 런타임 앱 역할 (DDL 불가, RLS 우회 불가)
CREATE ROLE cooa_app LOGIN PASSWORD '<COOA_APP_PASSWORD>'
  NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
-- 마이그/시드/grant는 테이블 소유자(또는 별도 cooa_migrator)로 수행.
```
> `cooa_app`이 **반드시 NOBYPASSRLS**여야 RLS가 의미를 가짐(`rls:audit`가 검증). dev 기본 비번 `cooa_dev_pw`는 prod 사용 금지.

> ⚠️ **[P0 컷오버 게이트] auth_lookup 브리지 함수 소유자 = BYPASSRLS 필수**: `accounts`·`organizations`는 **FORCE ROW LEVEL SECURITY**라 테이블 소유자도 RLS 대상(owner-bypass 무효). 로그인 전 크로스테넌트 발견을 담당하는 `auth_lookup_accounts`/`auth_lookup_invitation`(SECURITY DEFINER)은 **소유자가 superuser 또는 BYPASSRLS 보유 role일 때만** 후보를 반환한다. `structure.sql`을 적재하는 role(=함수 소유자)이 평범한 테이블 소유자면 브리지가 **0행 반환 → 전원 로그인 fail-CLOSED(보안 누출 아닌 전면 로그인 장애·컷오버 정지)**. 따라서 **migrator/owner role을 BYPASSRLS 속성으로 생성**하거나 superuser로 structure.sql을 적재하라. `rls:audit`는 cooa_app 관점만 검증하고 이 소유자 속성은 검증하지 않으므로 §8 스모크의 브리지 실효성 확인이 별도 게이트다.

> **[검증 스텝 — owner 프로비저닝(structure.sql 적재) 직후 즉시]** 함수 소유자의 BYPASSRLS 속성을 **직접 조회**한다. §8의 함수 호출 스모크는 실효성을 사후·간접 확인(known subject·verified email 필요)하지만, 아래 introspection은 **데이터·GUC 없이** 소유자 속성만으로 미스컨피그를 더 이르게 잡는다:
> ```sql
> SELECT p.proname, r.rolname, r.rolsuper, r.rolbypassrls
>   FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
>  WHERE p.proname LIKE 'auth_lookup%';   -- auth_lookup_accounts / auth_lookup_invitation
> ```
> 각 행의 `rolbypassrls`(또는 `rolsuper`)가 **`t`가 아니면** 브리지가 0행을 반환해 **전 사용자 로그인 전면 정지**(보안 누출 아닌 인증 장애·컷오버 중단)가 발생한다. 미충족 시 `ALTER ROLE <owner> BYPASSRLS` 부여 후 재검증하거나 superuser로 structure.sql을 재적재하라.

---

## 4. 환경변수
| 변수 | 런타임(앱=cooa_app) | 마이그/시드/grant(owner) |
|---|---|---|
| `COOA_DB_USER` | **미설정** → app_role(cooa_app) | **owner**로 설정(override가 이김) |
| `COOA_APP_USER` | `cooa_app`(기본) | — |
| `COOA_APP_PASSWORD` | **시크릿**(필수) | — |
| `COOA_DB_PASSWORD` | — | owner 비번(필요 시) |
| `COOA_TENANT_ID` | **필수**(SI silo 루트 org uuid; `TenantConfig`가 prod에서 blank면 raise) | 동일 |
| `GOOGLE_CLIENT_ID` | Google 소셜 로그인(직접 연결 — ADR-003 v0.4 개정 경로) | — |
| `GOOGLE_CLIENT_SECRET` | **시크릿** · redirect URI = `https://<app>/auth/google_oauth2/callback` | — |
| `KC_ISSUER` | `https://<keycloak>/realms/<realm>`(**KC 사용 시** — v0.4: 브로커는 기업 SSO 시점으로 유예, GOOGLE_* 만으로 부팅 가드 충족) | — |
| `KC_CLIENT_ID` | `cooa-rails` | — |
| `KC_CLIENT_SECRET` | **시크릿**(KC 사용 시) | — |
| `KC_REDIRECT_URI` | `https://<app>/auth/openid_connect/callback` | — |
| `SECRET_KEY_BASE` | **시크릿**(세션 암호화) | — |
| ~~`AR_ENCRYPTION_PRIMARY_KEY`~~ | **폐기(사문)** — v0.4 step-up 제거·initializer 삭제. 설정 불요 | ~~동일~~ |
| ~~`AR_ENCRYPTION_DETERMINISTIC_KEY`~~ | **폐기(사문)** | ~~동일~~ |
| ~~`AR_ENCRYPTION_KEY_DERIVATION_SALT`~~ | **폐기(사문)** | ~~동일~~ |
| `COOA_DB_HOST` | DB 호스트(default `localhost` — **관리형 Postgres면 필수**) | 동일 |
| `RAILS_ENV` | `production` | `production` |

핵심 seam(`database.yml`): **`COOA_DB_USER`가 설정되면 그 값(owner)으로, 미설정이면 `cooa_app`으로** 접속. 따라서 **마이그/시드/grant 명령에만 `COOA_DB_USER=<owner>`를 붙이고, 앱 프로세스에는 붙이지 않는다.**

> ⚠️ **AR_ENCRYPTION_* 3개는 owner·cooa_app·rake 등 모든 Rails 프로세스가 부팅 시 `config/initializers/active_record_encryption.rb`를 로드 → 하나라도 없으면 `raise`(부팅 불가)**. KC trio 중 **부팅 가드는 `KC_ISSUER`만**(나머지 `KC_CLIENT_ID`/`SECRET`/`REDIRECT_URI`는 미설정 시 부팅은 되나 OIDC 로그인이 요청 시점에 실패).

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

**앱(cooa_app) 스왑 전에** owner-크레덴셜 one-off로 `bin/release-migrate`를 선실행한다 — 아래 **1~3(마이그→grant→배포 게이트)을 게이트 체인 스크립트로 대체**한다(체크인 스크립트로 사람 누락 방지 · 재발명 아님 · DESIGN-운영-06-신뢰성 §2.2):
```
COOA_DB_USER=<owner> RAILS_ENV=production bin/release-migrate
```
스크립트 순서: **owner 가드**(접속 role이 BYPASSRLS/SUPERUSER 아니면 abort) → `db:migrate` → `rls:grant_app`(멱등) → `rls:audit`(**하드 배포 게이트**) → solid_* 안내. `set -e`로 어느 스텝이든 실패하면 즉시 중단(앱 스왑 안 함) — 1 성공→2, 3(`rls:audit`) abort 없어야→앱 스왑.
- **호출 배선(실 배포 대상 확정 시)**: Kamal `pre-deploy` 훅 또는 CI 파이프라인의 명시 "migrate" job이 owner 시크릿과 함께 호출(DESIGN-운영-06 §1.2b·§2.1). 현재 `.kamal/hooks/*`는 전부 `.sample` — 배포 대상 확정 후 배선.
- **앱 컨테이너엔 owner 시크릿(`COOA_DB_USER`/`COOA_DB_PASSWORD`) 미주입** — RLS 우회 방지(§10 정합). 엔트리포인트(`bin/docker-entrypoint`)도 prod에서 `db:prepare`를 스킵한다(`RAILS_ENV!=production || RUN_DB_PREPARE=1` 게이트 — cooa_app DDL 불가·fresh DB seed 가드 크래시루프 종결, DESIGN-운영-06 §1.2a).
- **fresh DB 최초 1회 부트스트랩**: 스키마가 비어 있으면 `bin/release-migrate`의 `db:migrate` 전에 owner로 스키마 적재가 선행돼야 한다 — `COOA_DB_USER=<owner> RAILS_ENV=production bin/rails db:schema:load` 후 `bin/release-migrate`(또는 엔트리포인트 `RUN_DB_PREPARE=1` + owner 크레덴셜). structure.sql가 RLS policy + audit 불변 트리거 보존, **GRANT는 strip**(그래서 매 릴리스 grant 재적용 필수).

**스크립트가 자동화하는 1~3 (참조) + 스크립트 밖 수동 4~5:**
1. **스키마+마이그** `db:migrate` — ⚠️ **`db:prepare` 금지**(fresh DB서 `db:seed`를 자동 실행해 데모 org/계정을 prod에 주입 — seed에 prod 가드 있으나 절차도 no-seed 경로). B2/B3 마이그(`20260630000001/2/3`)·P4 인덱스(`idx_ra_eligible_approver`)는 structure.sql에 baked.
2. **grant 재적용** `rls:grant_app` — cooa_app 권한(RLS 테이블 DML · read-only SELECT · **active_storage 3종 DML**(업로드 INSERT/analyze UPDATE/purge DELETE — 누락 시 업로드 500) · **audit_logs SELECT/INSERT만** · 시퀀스 USAGE). 스키마 로드 후 매번 필수 · 멱등.
   ⚠️ **solid_* 별도 DB grant(prod 전용·미자동화)**: `rls:grant_app`은 **primary DB에만** 적용된다. production은 solid_queue/solid_cache/solid_cable이 **별도 DB**(cooa_production_{queue,cache,cable})를 cooa_app으로 접속하므로, 권한이 없으면 **업로드 잡 enqueue 500(dev에선 재현 불가)**·캐시/케이블 전면 실패. 택1: (a) 세 DB의 **소유자를 cooa_app으로** 생성(권장 — 이후 solid 마이그 자동), 또는 (b) 각 DB에 `SELECT,INSERT,UPDATE,DELETE` + 시퀀스 USAGE 수동 grant. `bin/release-migrate`가 이 택1 안내를 echo한다(자동 실행 아님 — 인프라 결정).
3. **배포 게이트** `rls:audit` — 테넌트 테이블 RLS 누락 또는 cooa_app의 audit_logs UPDATE/DELETE 권한 있으면 abort → 앱 스왑 차단.
4. (최초/온보딩) prod org를 `COOA_TENANT_ID`로 생성 + 계정/role_assignment 프로비저닝. **데모 시드(db/seed) 사용 금지**(데모 데이터; seed에 prod 가드 내장). *(step-up/TOTP 등록 항목은 v0.4·2026-07-06 배너대로 사문 — 삭제됨.)*
5. 앱 기동(`COOA_DB_USER` 미설정 → cooa_app) → RLS end-to-end 강제.

cooa_app으로 마이그 금지(DDL 불가). 매 릴리스 "마이그 후 grant 재실행"이 `bin/release-migrate`로 스크립트 강제된다.

---

## 8. 컷오버 후 검증 (prod 스모크)
- `rls:audit` green(17 테넌트 + append-only 가드).
- cooa_app: 로그인 계정 조회·대시보드 SELECT·도메인 INSERT 가능 / `audit_logs` UPDATE·DELETE **거부**.
- OIDC: `<KC_ISSUER>/.well-known/openid-configuration` 200 → 브라우저 로그인 → 콜백 → 대시보드.
- `audit:verify` 체인 무결.
- **auth_lookup 브리지 실효성(§3 P0 게이트)**: 무-GUC(로그인 전) 상태에서 `SELECT * FROM auth_lookup_accounts('google_oauth2','<known-subject>','<verified-email>')`가 후보 행을 반환하는지 확인 — 0행이면 함수 소유자가 BYPASSRLS 미보유(전면 로그인 정지 원인). owner-provisioning 직후 필수.
- 로컬 picker 라우트(`/session/new`) **404**(prod).
- **AR 암호화 라운드트립**: 던질 계정에 `provision_totp!` → `account.totp_secret` 평문 복호화 성공(키가 단지 non-blank가 아니라 *정확*함 = step-up 실작동 보장; 부팅됨 ≠ 복호화됨).
- **step-up e2e**: 결재자 `/step-up` 등록 → 유효 TOTP로 submit→approve → `approval_steps.re_auth_at` 세팅·`re_auth_factor='totp'`·`signed_c1_digest` 채워짐 + `outcome='allow'` audit. 음성: 빈/오답 코드 → `deny step_up_failed`; 미등록 → `step_up_not_enrolled` + `/step-up` 리다이렉트.

---

## 9. 전송·세션 하드닝
- `config.force_ssl = true` **활성화됨**(`production.rb`) → Secure 쿠키·HSTS·http→https. ⚠️ **upstream(LB/리버스 프록시)이 TLS 종단이면 `force_ssl` 대신 `config.assume_ssl = true`로 바꿔라**(이중 리다이렉트 방지·프록시 헤더 신뢰) — cutover 시 인프라에 맞춰 택1.
- `SECRET_KEY_BASE` 시크릿. 세션 쿠키 httpOnly/SameSite(Rails 기본) 확인.
- revocation: 매요청 `token_version`/status 재검사(suspend/deprovision/역할변경 시 `Account#bump_token_version!`) — 코드 내장. idle timeout 60분.

---

## 10. 롤백
- 직전 릴리스로 되돌림. owner/cooa_app 분리·grant는 **멱등**(`rls:grant_app` 재실행 가능). 스키마 다운마이그는 신중(RLS/트리거 포함).
- 긴급 시 dev처럼 owner로 앱 기동(`COOA_DB_USER=<owner>`)은 **RLS 우회**가 되므로 prod 금지(진단 한정).
- **AR_ENCRYPTION_* 키 영구**: 롤백 시에도 **동일 키 유지**(재생성/다른 시크릿스토어 = 전 `totp_secret` 복호화 불가 → approve 500; 데이터 파괴는 아님, 재등록 복구).
- **아티팩트(이미지) 롤백 우선, down-migration 지양**: 추가 컬럼은 이전 코드와 backward-compat(무시됨)라 **컬럼은 두고 릴리스 아티팩트만** 되돌려라(down-migrate + 신규 코드 = 없는 컬럼 참조 크래시). B2 `totp_secret` 드롭은 전 결재자 enrollment 소실(의미적 lossy).
- **B3 불변식**: `audit_logs` impersonation 3컬럼은 **impersonation row 0건일 때만 드롭 안전**(2a는 writer 코드경로 없어 안전). 사용 후 드롭 시 `canonical_body` 재계산 불일치 → `audit:verify` 실패 + 불변 트리거로 수리 불가.

---

## 11. 연기/오픈 항목 (ADR §13)
- 멀티테넌트 SaaS의 host→tenant 해석(현재는 SI silo `COOA_TENANT_ID` 상수).
- invitation 기반 JIT 프로비저닝(현 email-link)·MFA step-up·승인 위임·다시장 roll-up.
- `audit_logs` 보존/아카이브 정책(7년 무결).
- vestigial `screening_runs` 승인 컬럼(status/approved_by_id/approved_at) 드롭 마이그.
- AI-엔진 데이터 인프라(Qdrant/OpenSearch/BGE-M3)는 **별개 트랙**(이 런북 범위 밖).

---

## 12. 운영 SOP (P4 — 스케일/운영 검증)
**키 로테이션 (시크릿)**
- `COOA_APP_PASSWORD`(cooa_app): `ALTER ROLE cooa_app PASSWORD '<new>'` → 시크릿 매니저 갱신 → 앱 롤링 재시작. (미설정 시 prod는 부팅 fail-fast — `database.yml`)
- `KC_CLIENT_SECRET`: Keycloak에서 client secret 재발급(kcadm/REST) → 시크릿 갱신 → 재시작.
- `SECRET_KEY_BASE`: ⚠️ 로테이션 시 **세션 쿠키 암호화 키가 바뀌어 전 세션 무효화**(강제 전체 로그아웃). 무중단 필요 시 `secret_key_base` rotations 설정 후 단계적 폐기.
- **`AR_ENCRYPTION_*` (3개)**: ⚠️ **미설정=부팅 fail-fast(안전)** vs **잘못된 키로 교체=부팅은 되나 복호화 시점 실패** → 전 approve가 step-up에서 dead-end. 현 initializer엔 **`previous:` 키체인 미배선 → graceful 로테이션 경로 없음**: (i) initializer에 `previous` 키리스트 추가 후 re-encrypt, 또는 (ii) "로테이션 = fleet 전체 totp 재등록" 수용·문서화 중 택1(fast-follow). **백업/복원**: DB 스냅샷은 *그 시점의 AR 키 세대와 짝지어* 보관(다른 세대로 복원 = 전 시크릿 사망).

**커넥션 풀링**
- `TenantContext.with_tenant`는 `set_config(...,true)`=**SET LOCAL**(트랜잭션 경계) → **PgBouncer 트랜잭션 풀링 모드 지원**(session 풀링 불필요; 세션 레벨 SET/prepared state 없음). 풀드 컷오버 시 transaction pooling 사용.

**백업/복원 vs 해시체인**
- domain+audit 정합을 위해 **단일 일관 스냅샷**(PITR 또는 단일 트랜잭션 덤프) 강제. 부분 백업 혼합 금지.
- `audit:verify`는 **tail 절단(최근 이력 유실)을 못 잡음**(1..N 연속이면 PASS) — 복원 후 최신 `tenant_seq`를 외부 기록과 대조.

**모니터링**
- **감사 야간 스캔 = owner 외부 스케줄(`bin/audit-scan` + `.github/workflows/audit-scan.yml`)**. ⚠️ **`config/recurring.yml` 직등록 금지**: SolidQueue는 recurring 잡을 **cooa_app(FORCE RLS)로 디스패치**해 타 테넌트 행을 은폐 → `audit:verify`/`detect_bola`가 1개(또는 0) 테넌트만 보고 **"이상 없음" 위양성(은폐된 무점검)**을 낸다(DESIGN-운영-07 §1.1 · 02 §5.2). 그래서 **owner(BYPASSRLS)로 스케줄 밖**에서 실행한다. `bin/audit-scan`: owner 가드 → `audit:verify`(exit≠0=체인 파손 **SEV1**) + `MINUTES=1440 audit:detect_bola`(야간 창·exit≠0=BOLA **SEV2**) → 종합 → `AUDIT_WEBHOOK_URL` 설정 시 얇은 JSON POST(🟢 uuid·카운트·SEV만 · 미설정이면 로그만). GHA 크론(야간)이 이를 호출하되 **secrets 주입·prod DB에 닿는 러너 배선은 실 배포 대상 확정 후**(preflight 가드가 그전까지 스킵 → 빈 리포 red 방지). 알림 라우팅 상세=DESIGN-운영-02 §5.3(BOLA 급증=SEV2 메신저 · `audit:verify` FAILED=SEV1 페이지).
- 배포 게이트 `rls:audit`(+`rls:grant_app`·`db:migrate`)를 **체크인 릴리스 스크립트 `bin/release-migrate`로 고정**(사람 누락 방지·§7). 서버측 블로킹 CI 승격은 DESIGN-운영-06 §2.1.
- **잡 영구 실패 관측(E6)**: `solid_queue_failed_executions`를 주기 점검 — 비어있지 않으면 preprocessed 썸네일 변형 등 잡의 영구 실패 신호다. `ApplicationJob`은 일시 오류(`ActiveRecord::Deadlocked`)만 재시도하고 ActiveStorage 손상/포맷 오류는 재시도 없이 실패로 적재되므로, 이 테이블이 1차 관측면이다(예외 상세는 `Rails.error` 구조화 로그 `[error_report]`). 알림 싱크는 2b.

## 13. 2b 스케일 게이트 (트리거 명시 — 2a에선 손대지 말 것)
- **audit_logs RANGE 파티셔닝(by `ts`) + DROP 아카이빙** — 불변 트리거가 DELETE 차단 → DROP만이 purge 경로. 트리거: 풀드 전환 OR 단일테이블 >~1천만 행.
- **요청-수명 트랜잭션 풀 점유** — `scope_to_tenant`가 액션+렌더 전체를 1 tx로 핀. 트리거: 2b 부하테스트서 connection 고갈 관측.
- **`detect_bola` 알림 채널** + **`rls:audit`/`audit:verify` 블로킹 CI 스텝** — 트리거: 풀드 SaaS 출시 전.
- **advisory lock 32-bit 충돌**(`hashtext(uuid)`) — 트리거: 테넌트 수천 도달(정확성은 `UNIQUE(tenant,seq)`가 보증, throughput만).
- **dashboard `tree_preorder` N+1**(루트만 preload) — 트리거: 대형 제품트리. flat 로드+Ruby 그룹핑으로 O(1) 쿼리화.
- **`users` 테이블 tenant_id+RLS**(2a RLS-면제) — 트리거: pooled 멀티테넌트(freeze spec §5).
- **인덱스**: `idx_ra_eligible_approver`(P4 ②)는 이미 추가(2a 무영향·2b 헤지). silo의 0-선택도 `tenant_id` 인덱스는 2b 풀드에서 발효.

---

> **프로덕션 준비도 전반**은 vault `_기술/AI아키텍처/REF-프로덕션-준비도-지도.md`(2026-07-06 6축 감사)로 통합됨 — P0 3건(부팅 마이그 순서·백업 구현·§3 BYPASSRLS 게이트)·P1 11건·P2 이월. 이 §14/§13/§11 이월 항목의 "준비도 상태"도 그 지도에 반영. 런북=절차(how), 지도=준비도(what).

## 14. 거버넌스 소속 정리 (Stage 5 — 트랙 재배정)

Stage 5 확정판이 grab-bag 거버넌스 항목을 판정 압축하며 **코드로 만들지 않고 소속 트랙만** 명시해 이월했다. 여기에 "어디서 다뤄지는가"를 고정한다(스코프 크리프 방지 — 2a 리뷰 워크스페이스에서는 손대지 않는다).

### (a) 배포 인프라 트랙 (2b/pooled 스케일 게이트 — §13에 귀속)
아래는 **배포·스케일 인프라의 문제**이지 제품 기능이 아니다. 트리거는 §13과 동일(풀드 전환 or 규모 임계). ⚠️ 여기서의 "2b"는 **배포 스케일 게이트(§13)**를 가리키며, 제품 스펙의 **REF v2b 아크와는 별개**다(이름만 겹치는 다른 "2b" — 혼동 금지).
- **legal hold(법적 보존)** — audit_logs는 이미 불변 트리거로 append-only(§13-1 RANGE 파티셔닝·DROP 아카이빙과 한 묶음 — 홀드는 파티션 DROP 예외로 구현). 도메인 행 홀드는 (b) soft-delete 설계에 의존.
- **break-glass writer(긴급 우회 쓰기)** — 2a엔 writer 코드경로 없음(§10 B3 불변식: impersonation 3컬럼은 row 0건일 때만 드롭 안전). 실제 우회 쓰기 경로는 풀드 운영 트랙에서 감사 하네스와 함께 도입.
- **retention/파티셔닝** — audit_logs RANGE 파티셔닝(by `ts`) + DROP 아카이빙(§13-1). 보존 정책(7년 무결)은 §11 연기 항목과 짝.
- **detect_bola 알림 채널** — 초기 owner 야간 스케줄 + 웹훅 싱크는 **`bin/audit-scan`(+GHA)로 배선됨**(§12 모니터링 · recurring.yml 직등록 금지 — cooa_app RLS 은폐). 2b 이월은 **관리형 온콜 도구(PagerDuty/Opsgenie) 에스컬레이션**뿐(§13-3 · DESIGN-운영-02 §4.2 — 초기 메신저 웹훅과 분리).

### (b) 별도 설계 사이클 (ADR-002 §16-6 추출 후)
- **soft-delete(논리 삭제)** · **퇴사자 인계(offboarding handover)** — 삭제 의미론(hard vs soft)·소유권 이전·고아 방지·감사 정합이 얽힌 별도 설계다. **ADR-002 §16-6로 추출**한 뒤 독립 설계 사이클에서 다룬다(Stage 5 범위 밖 · 배포 인프라 게이트와도 분리된 제품/데이터 모델 결정).
