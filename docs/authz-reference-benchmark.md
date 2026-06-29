# COOA 권한 아키텍처 — 레퍼런스 대조 (P5)

> 웹 리서치 기반 벤치마크(2026-06). 우리 결정이 업계 표준인지/임의제작인지 + keep/change/add.
> 출처: AWS Prescriptive Guidance·Crunchy·Citus·Azure tenancy-models·PlanetScale / Oso·Cerbos·OpenFGA·Google Zanzibar·EnterpriseReady / FDA 21 CFR Part 11·eIDAS·NIST SP 800-63B·W3C WebAuthn·RFC 3161 / OWASP·Keycloak.

## 총평
**4개 영역 전부 업계 표준에 강하게 부합 — 임의·비표준 아님.** 오히려 흔한 실수를 선제 회피했다: FORCE+비소유자 롤(RLS #1 실수), `email_verified` 게이트(OIDC 계정탈취 정석), stateless JWT 거부(OWASP 권고). **C1 reviewed-tuple은 상용 e-sign보다 우수한 최상급 설계.** 진짜 갭은 **단 둘, 모두 의도적으로 식별·연기**: ① 서명시 step-up 부재(Part-11 §11.200 / NIST AAL2 블로커), ② 감사체인 외부 타임스탬프 앵커 부재(2b 가산). 어느 것도 설계 막다른 길이 아니라 전부 가산적(additive).

## 벤치마크 표
| 결정 | 우리 선택 | 업계 표준 | 판정 | keep/change/add |
|---|---|---|---|---|
| 테넌트 격리 RLS | FORCE+fail-closed(GUC→NULL)+비-BYPASSRLS 롤+복합FK | AWS/Crunchy/Citus 명시 권고 | **표준적** | KEEP / ADD: GUC-부재→0행 fail-closed CI 테스트 ✅(P5) |
| SI-silo→pooled | DB-per-tenant→공유+RLS | Azure tenancy graduation | **표준적** | CHANGE: 컷오버를 SET LOCAL·PgBouncer **transaction** 모드 계약에 게이트 |
| 인가 코드매트릭스 | Pundit + Ruby 하드코딩 role→verb (PDP 아님) | Oso/Cerbos "90% rule"=시작점 정석 | **표준적/수용** | KEEP / CHANGE: 단일 SoT+골든테스트(드리프트) / ADD: 외부화 5트리거 ADR 명문화 |
| RBAC vs ReBAC | RBAC+scoped grant(scope/market/expiry)+신원SoD | "RBAC+ABAC 오버레이"=2025 주류 | **표준적/수용** | KEEP / ADD: scope를 `(subject,relation,object)` 투영가능 설계(무재작성) |
| 승인 C1+two-eyes | SHA256(내용+아트워크+verdict+버전) submit캡처·sign재확인 | Part-11 §11.70·eIDAS-d·FIDO Tx Confirmation | **최상급** | KEEP(약화금지) / CHANGE: §11.50 트리플릿(인쇄명·UTC·의미) 1급필드 |
| step-up/e-sign | 서명시 재인증 **미구현** | §11.200·NIST AAL2·eIDAS-c | **임의-재고(블로커)** | ADD(최우선): WebAuthn/FIDO2(+TOTP), C1해시 결속 → **P6** |
| append-only 해시체인 감사 | 테넌트당 prev→chain, 불변 트리거 | §11.10(e) tamper-evident 인정 | **표준적** | KEEP / ADD: RFC 3161 TSA 외부앵커(백데이팅 차단, 2b) |
| 세션+token_version | 서버세션+매요청 무효화, JWT 거부 | OWASP: 서버측 취소 "필수" | **표준적(더 적합)** | KEEP / ADD: Keycloak Back-Channel Logout, idle+absolute 타임아웃 |
| OIDC RP | discovery·PKCE S256·`email_verified` 게이트 | Keycloak 권고 정합 | **표준적** | KEEP(`email_verified` 방어파싱 ✅ P2) |

## 권고 — 우선순위
**지금(2a 경화)**: ① RLS GUC-부재 fail-closed 테스트 ✅(P5 반영) · ② `verify_authorized` 전경로 ✅(기존) · ③ `email_verified` 방어파싱 ✅(P2) · ④ 인가매트릭스 SoT+골든테스트(드리프트 — AI코어 분리 전 선결, 현재는 `Actions.valid?`+policy_matrix_test가 부분 가드).
**2b 도입**: step-up(P6) · Keycloak back-channel logout · RFC 3161 TSA 앵커 · 컷오버 GUC 계약 게이트 · scope 튜플 투영.
**의식적으로 다르게(정당·유지)**: stateless JWT 거부(규제 e-서명은 취소불가 토큰 불용) · ReBAC 미채택(공유그래프 없음 → scoped-grant로 충분) · 외부 PDP 미도입(단일 모놀리스=90% 규칙; 트리거=AI코어 분리/테넌트정의 역할 → Cerbos).

## 검증 영향 (P1~P4 분류 지지)
- **step-up = 2a 블로커 확정**: §11.200(비연속 서명=전체 재요구)·NIST AAL2(현존 증명)·eIDAS-c(단독 제어) 세 규제선이 독립 수렴 → 장시간 Rails 세션은 서명용 "연속 통제접근 세션"이 아니므로 매 서명 재인증 필수. C1(내용바인딩)은 §11.70 충족하나 **서명자 인증과 직교**라 대체 불가 → 갭 실재. **P6 사양 대상.**
- **ReBAC = 2b 확정**: 지금은 과설계. 단 scope 테이블을 튜플 투영 가능하게 설계할 **선제 의무** 부과("나중에"≠"무대비").
- **2레이어 인가 정합**: RLS는 Pundit 대체가 아닌 방어심층 하위층(RLS는 쿼리실행/DoS 못 막음) 재확인.
- **신규 2b 가산**: Keycloak back-channel logout 미연동 · 감사체인 외부앵커 부재.
