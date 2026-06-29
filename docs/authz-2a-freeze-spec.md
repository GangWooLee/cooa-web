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
- ❌ `policy_version` 컬럼 존재하나 **미주입**(default 0); `on_behalf_of`/`impersonation_context` 컬럼 부재.

## 2. 갭 4분류 원장
| bucket | 항목 |
|---|---|
| **DONE** | RLS 17·합성FK·cooa_app·SET LOCAL·서버 tenant·OIDC·token_version 폐기·세션회전·SoD·M1/M2·C1 재검증·해시체인 |
| **2a-blocker** | **step-up(TOTP)** · **break-glass**(+audit on_behalf_of/impersonation_context 컬럼) · **last-owner zero-window 가드** |
| **2a-fix-bug** | **policy_version 주입**(MATRIX_VERSION 배선) |
| **2b-backlog** | RAG격리 · ComponentVersion TOCTOU 비관락 · quorum/join-rule · product/component-scoped role · region RLS · SCIM · 초대토큰 · 7년보존 · crypto-shred · audit 조회 게이트 |
| **cut** | tier-SSO · 조직계층(reporting_edge) · delegation 엔진 · HRD/multi-org · multi-market roll-up |

## 3. 데드코드/스텁 처리
- **SI_LEAN 동사**(share_findings 등): **데드 아님(활성)** — 매트릭스에 wired. 유지.
- **delegate_approval**: 매트릭스 천장만(행위 0). keep-with-doc("Phase3+ join-rule 전까지 무동작"). `Actions.valid?` 정합 위해 ALL 유지.
- **impersonate_tenant**: break-glass PDP 동사 자리. cooa_staff=[]라 미부여(fail-closed). break-glass 빌드 시 발효. 제거 금지.
- **AssignmentResolver scope_id:nil**: **스텁 아님 = 의도적 2a lean**. "scope_id≠NULL = 2b" 주석 유지.

## 4. 2a 완성에 필요한 것 (동결 전 참이어야 함)
1. **[blocker] step-up TOTP** — approval_steps에 re_auth_at/factor 추가 + TOTP 챌린지·검증 + reviewed_* digest 서버바인딩 + 성공 후 세션 회전. (규제 e-서명 법적유효성)
2. **[blocker] break-glass** — impersonation_session + RFC8693(aud=target) + PDP가 impersonation_context면 approve/서명 거부 + audit on_behalf_of/impersonation_context 컬럼 + 상시배너. (XL)
3. **[blocker] last-owner 가드** — deprovision/suspend 전 active-owner 카운트, 0이면 거부/`pending_owner_recovery`. (S; recovery는 break-glass 재사용)
4. **[fix-bug] policy_version 주입** — MATRIX_VERSION(또는 git SHA) → 모든 AuditLog.record!에 바인딩. (1~2h)
5. **[doc] TOCTOU 명시** — approve 경로 "SI=best-effort staleness, pooled=비관락 2b" 주석 + 테스트.

## 5. 동결 판단: CONDITIONAL NO-GO → 위 1~4 해소 시 SAFE TO FREEZE
- **위험한 구멍 0** — 미구현은 전부 안전한 연기(RLS+합성FK가 Postgres층을 닫음).
- ⚠️ **`users` 테이블 = RLS-면제 + cooa_app 전역 SELECT**(PII: name/email; tenant_id 컬럼 없음). 2a(SI-silo = DB당 단일 테넌트)에선 교차테넌트 공존이 없어 **무해**하나, **pooled 2b 전환의 필수 게이트**: users에 tenant_id+RLS 추가 또는 신원 분리(PII는 테넌트 스코프). (P2 m-7)
- break-glass 부재 = **라이브 취약점 아님**(`cooa_staff=[]` fail-closed, cross-tenant 코드경로 0) — 단 ADR-003:318 연기불가 전제라 **출하-미완**.
- last-owner: SI는 DB레벨 복구 가능(잔여위험 낮음)이나 비용 S라 **2a 유지 확정**.
- 코드버그(OIDC 초대게이트·GUC·N+1·TOCTOU·audit-grant 테스트)는 **P2/P3/P4 범위**(누락 아님). TOCTOU의 2b 잠정분류는 **P2 적대 재검증**.
