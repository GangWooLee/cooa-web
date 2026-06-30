# COOA 권한 시스템 — 2a as-built 동결 사양 (P1 산출)

> 기준 스냅샷: 2026-06-29, `feat/foundation-tenant-rls`, 마이그 20260628000001~20260629000003. 160 테스트.
> 이 문서 = 권한 시스템 다이어그램(매트릭스·인가흐름·승인 상태머신·인증흐름)의 **진실원천(as-built)**.
> "2a" = SI-silo 파트너에 격리·신원·규제서명·감사 실발효로 출하 가능한 지점. "2b" = SaaS/Enterprise(SCIM·WebAuthn·pooled).

## 1. as-built 동결 사양 (서브시스템별 — 실제 wired된 것만)

### 격리 (Postgres RLS)
- 17 테넌트 테이블 전부 `ENABLE + FORCE ROW LEVEL SECURITY`, 정책 `tenant_id = NULLIF(current_setting('app.current_tenant_id', true),'')::uuid`(fail-CLOSED).
- 부모-자식 **15 합성 FK** `(tenant_id, fk)→parent(tenant_id, id)`; `role_assignments→organizations`·`accounts→organizations`만 단일컬럼(루트라 합성 무의미 = 정확).
- 런타임 `cooa_app`(**NOBYPASSRLS**): RLS 14테이블 DML, READ_ONLY 4 SELECT, **audit_logs = SELECT/INSERT만**(+ 불변 트리거).
- 매 요청 `around_action`이 명시 트랜잭션 안 `set_config(...,true)` = **SET LOCAL**(풀 누출 없음). `tenant_id`는 ENV(`COOA_TENANT_ID`) **서버해석**, 클라 클레임 불신; `validate_tenant_match` 교차테넌트 세션 차단.
- ❌ RAG/벡터 격리 미존재(AI코어 미착수 → 라이브 표면 아님).

### 인증·세션
- Keycloak **OIDC RP**(discovery+PKCE S256, uid=sub→idp_subject) + **Rails 서버측 세션**. `reset_session`(고정 방어) 후 `account_id`+`token_version` 바인딩.
- **매 요청 폐기 발효**: `verify_revocation`이 RLS tx 안 fresh Account 재조회 → `active?` AND `token_version` 일치 아니면 세션리셋(sub-second).
- ❌ 미빌드: approve step-up(TOTP/re_auth_at)·break-glass·초대토큰·SCIM·tier-SSO·region RLS 강제.

### 인가·역할
- **DB 권한테이블 없음** — 8역할×액션 매트릭스가 **코드(`permission_matrix.rb`)에 ADR-002 §6 전사**, 어휘는 `actions.rb`에 동결(`Actions.valid?` 드리프트 차단).
- 역할 해석 `RoleResolver` swap면(Phase1 Demo / Phase2 Assignment). 현 `AssignmentResolver`는 **`scope_id: nil`(테넌트-와이드) 부여만** 발효(product/component 스코프는 2b).
- SoD = **신원기반**(Account.user_id bigint로 제출자≠결재자). `cooa_staff => [].freeze`(상시권한 0, break-glass 전용).

### 승인
- `approval_request`가 **C1 reviewed-tuple** submit 시 캡처(artifact_digest·content_snapshot_hash·ruleset/engine/disclaimer 버전·verdict_snapshot). M1(eligible_approver, 0이면 `blocked_no_approver`)·M2(self-approve 거부, owner 포함) 발효. approve 시 `ReviewedTuple.stale?` 재검증(text-over-artwork 방어).
- **two-eyes 단일 step**(`UNIQUE(tenant_id, approval_request_id)`).
- ❌ 미빌드: approval_step에 re_auth_at/factor(step-up 자리 없음)·quorum·ComponentVersion 비관락.

### 감사
- append-only(BEFORE UPDATE/DELETE 트리거 + FORCE RLS) **해시체인** SHA256(prev‖canonical), `audit:verify` 갭탐지. allow/deny 양쪽. 전이=요청 tx와 원자적.
- `policy_version`는 매 row에 `MATRIX_VERSION` 주입(P2 M-3 ✅). ❌ `on_behalf_of`/`impersonation_context` 컬럼 부재(break-glass P6와 함께).

## 2. 갭 4분류 원장
| bucket | 항목 |
|---|---|
| **DONE** | RLS 17·합성FK·cooa_app·SET LOCAL·서버 tenant·OIDC·token_version 폐기·세션회전·SoD·M1/M2·C1 재검증·해시체인 |
| **2a-blocker → BUILT** | step-up TOTP(**B2** ✅ 서명 재인증·c1_digest 결속·재인증 증거) · last-owner 가드(**B1** ✅ 모델 불변식+advisory-lock) · break-glass audit provenance 3컬럼(**B3** ✅ nil-생략). owner-recovery _임퍼소네이션 플로우_ = 추적 fast-follow(B1이 공통 zero-owner 차단·B3가 감사 토대 선설치) |
| **2a-fix-bug → DONE(P2)** | policy_version 주입 ✅ · C1 TOCTOU atomic 재검 ✅ · OIDC BOLA ✅ · deny-감사 GUC ✅ (P2에서 전부 해소) |
| **2b-backlog** | RAG격리 · ComponentVersion TOCTOU 비관락 · quorum/join-rule · product/component-scoped role · region RLS · SCIM · 초대토큰 · 7년보존 · crypto-shred · audit 조회 게이트 |
| **cut** | tier-SSO · 조직계층(reporting_edge) · delegation 엔진 · HRD/multi-org · multi-market roll-up |

## 3. 데드코드/스텁 처리
- **SI_LEAN 동사**(share_findings 등): **데드 아님(활성)** — 매트릭스에 wired. 유지.
- **delegate_approval**: 매트릭스 천장만(행위 0). keep-with-doc("Phase3+ join-rule 전까지 무동작"). `Actions.valid?` 정합 위해 ALL 유지.
- **impersonate_tenant**: break-glass PDP 동사 자리. cooa_staff=[]라 미부여(fail-closed). break-glass 빌드 시 발효. 제거 금지.
- **AssignmentResolver scope_id:nil**: **스텁 아님 = 의도적 2a lean**. "scope_id≠NULL = 2b" 주석 유지.

## 4. 2a 완성에 필요한 것 (동결 전 참이어야 함)
1. ~~[blocker] step-up TOTP~~ → **B2 완료** — approval_steps.re_auth_at/factor/signed_c1_digest + TOTP 검증 + c1_digest 서버바인딩. (WebAuthn Phase B는 fast-follow)
2. ~~[blocker] last-owner 가드~~ → **B1 완료** — Account/RoleAssignment 모델 불변식이 마지막 active owner 정지·강등·제거 거부(advisory-lock 직렬화).
3. **[blocker] break-glass** → **B3 부분(audit provenance 3컬럼 발효)**; owner-recovery 임퍼소네이션 플로우(impersonation_sessions·two-staff·PDP 서명거부)는 **fast-follow**. 근거: B1이 zero-owner 공통경로를 예방하므로 드문 안전망. ops/incident 풀 임퍼소네이션은 **waiver→2b**(SI-silo는 파트너 DBA가 커버).
4. ~~[fix-bug] policy_version 주입~~ → **P2 M-3 완료**(`MATRIX_VERSION` 주입).
5. ~~[doc] TOCTOU 명시~~ → **P2 M-2 완료**(stale 재검을 `approve!` 트랜잭션 내부로; 전체 락-조율만 2b 잔류, `approval_request.rb` 주석).

> **P2 완료**: 위 4·5 + OIDC BOLA·deny-감사 GUC 해소. 남은 2a 블로커 = **step-up·break-glass·last-owner**(전부 기능, P6 사양).

## 5. 동결 판단 (P7 종합): **GO — SAFE TO FREEZE** ✅

7단계 검증 + 빌드 완료: P1 동결사양 → P2 보안 적대검증(게이트4+잔여3 수정·독립리뷰) → P3 코드품질(**견고·과설계 아님**) → P4 확장성(N+1 SQL화·인덱스) → P5 레퍼런스대조(**전영역 업계표준·C1 최상급·임의제작 아님**) → P6 블로커 사양·결정 → **B1**(last-owner) **B2**(step-up TOTP) **B3**(감사 provenance) 빌드. **156 green · rls:audit 17 + append-only · audit:verify 무결.** Critical/Major 보안버그 0 · 코드 솔리디티 통과 · 확장성/운영 결함 해소 · 아키텍처 결정 레퍼런스 검증 · 2a 블로커 빌드/결정 완료.

**잔여(비차단 fast-follow)**: owner-recovery 임퍼소네이션 플로우(B1이 공통경로 차단·B3 감사토대 선설치) · step-up WebAuthn Phase B · Keycloak back-channel logout · RFC3161 TSA 외부앵커. 전부 가산적, 동결 차단 아님.

- **위험한 구멍 0** — 미구현은 전부 안전한 연기(RLS+합성FK가 Postgres층을 닫음).
- ⚠️ **`users` 테이블 = RLS-면제 + cooa_app 전역 SELECT**(PII: name/email; tenant_id 컬럼 없음). 2a(SI-silo = DB당 단일 테넌트)에선 교차테넌트 공존이 없어 **무해**하나, **pooled 2b 전환의 필수 게이트**: users에 tenant_id+RLS 추가 또는 신원 분리(PII는 테넌트 스코프). (P2 m-7)
- break-glass: **audit provenance 토대 발효(B3)** + owner-recovery 플로우 fast-follow. `cooa_staff=[]` fail-closed라 **라이브 취약점 아님**. ops/incident 풀 임퍼소네이션은 waiver→2b(SI-silo DBA 커버).
- last-owner: **B1 빌드 완료** — Account/RoleAssignment 모델 불변식이 zero-admin lockout을 원천 차단(advisory-lock 직렬화).
- 코드버그(OIDC 초대게이트·GUC·N+1·TOCTOU·audit-grant 테스트)는 **P2/P3/P4 범위**(누락 아님). TOCTOU의 2b 잠정분류는 **P2 적대 재검증**.

## 6. Fast-follow 백로그 (배포 후·비차단 — 단일 소스)
2a는 동결 GO. 아래는 *가산적*이라 동결을 막지 않으며, 우선순위순으로 처리한다(중복 추적 방지 = 이 섹션이 단일 소스).

**Fast-follow (2a 직후 우선):**
- **owner-recovery 임퍼소네이션 플로우** — B1이 zero-owner 공통경로 차단·B3가 감사 provenance 컬럼 선설치. 남은 것: `impersonation_sessions` 테이블 + two-staff 승인 + PDP 서명거부 + UI. (P6 #2 설계 완료)
- **step-up WebAuthn Phase B** — 현 `/step-up`은 평문 시크릿 노출·QR 미지원(TOTP Phase A). WebAuthn/FIDO2(피싱저항 AAL2, P5 우선) + QR 등록 UX.
- **AR_ENCRYPTION_* graceful 로테이션** — initializer에 `previous:` 키체인 배선(현 단일 키 = 로테이션 시 fleet 재등록). (배포준비 감사 발견)
- **데모 step-up 단락 옵션** — web-demo에 결재 노출 시 `local_login_enabled` 게이트에 데모 한정 step-up 단락 PR(prod always-on 불변 유지). (배포준비 감사 발견)

**2b 백로그 (pooled SaaS/Enterprise — 트리거 구동):**
- Keycloak back-channel logout · RFC3161 TSA 외부 타임스탬프 앵커 · `users` tenant_id+RLS(pooled 게이트) · SCIM/디프로비전 · 초대 single-use 토큰 · crypto-shredding(PIPA) · region RLS 강제 · product/component-scoped grant(ReBAC 트리거) · audit RANGE 파티셔닝·7년 보존 · RAG/벡터 격리 · 외부 PDP(Cerbos — AI코어 분리=다중서비스 트리거).

> 상세 트리거·근거: P5 `docs/authz-reference-benchmark.md` · P4 `docs/prod-cutover.md` §13(2b 스케일 게이트) · 메모리 [[cooa-rbac-authz-design]]·[[cooa-auth-adr003]].
