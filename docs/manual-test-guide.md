# COOA 권한 시스템 — 손에 잡히는 수동 테스트 체크리스트

> 목표: `bin/dev`로 띄운 데모를 직접 클릭·콘솔·rake로 만지며 권한 시스템이 **어디까지·어떻게** 만들어졌는지 체감한다. 페르소나·콘솔·rake는 실제 코드(`/Users/igangu/COOA/web`)에서 추출.
>
> 리뷰 모델은 **경량 "버전 리뷰"**다: 리뷰어가 한 버전을 **검토 확인**하거나, 고칠 점은 아트워크에 **피드백**(annotation)으로 남긴다(별도의 "변경 요청/반려" 상태 없음). 리뷰는 **버전 뷰**(`/versions/:id`)의 "버전 리뷰" 패널에 앵커된다(스크리닝 비의존 — 디자이너는 스크리닝 없이 요청, RA가 검토 중 스크리닝). SoD(요청자≠확인자)·stale 가드·감사는 그대로.

---

## 0. v1.5 통합 데모 스크립트 (팀 데모용 · 한 번에 흐르는 대본)

> 각 줄 = **[로그인 페르소나]** 행동 → *기대 화면*. 상세 메커니즘·변형은 괄호의 § 참조(중복 서술은 그쪽에).
> 실행 §1-1(`bin/dev`) · 페르소나/이메일 §1-2 · 버전 리뷰 패널 도달 경로 §1-4.

### ① 품질 크로스컷 리뷰 — 미배정 제출 → 인박스 대기큐 → 내가 맡기 → 검토 확인
1. **[박쿠아·SCM]** 버전 리뷰 패널(§1-4)에서 리뷰어 미지정으로 **"리뷰 요청"** → *패널이 "리뷰 대기 / 요청됨"(주황)으로 전환* (§3.1)
2. **[이쿠아·RA]** 사이드바 **"내 리뷰 인박스"**(`/reviews`) → *"리뷰어 미배정 — 내가 맡을 수 있는 리뷰"(Segment B) 큐에 그 버전이 보임* (§3.5)
3. **[이쿠아]** 그 카드의 **"내가 맡기"** → *"내게 요청된 리뷰"(Segment A)로 이동 + 사이드바 배지 +1* (§3.5)
4. **[이쿠아]** 버전 뷰로 가 **"✓ 검토 확인"** → *패널이 초록 "✓ 검토 확인됨 · 이쿠아 · 시각"* (§3.3)

### ② 법무 크로스컷 리뷰 — 동일 절차, 다른 버전·리뷰어(검토 도메인만 교체)
- **[박쿠아]** 다른 버전을 미지정으로 **"리뷰 요청"** → **[김쿠아·owner]** 인박스에서 **"내가 맡기"** → 버전 뷰 **"✓ 검토 확인"**. *①과 완전히 같은 흐름을 다른 신원(법무 검토)으로 재현*. 고칠 점이 있으면 확인 대신 아트워크에 **피드백**(Shift+드래그 annotation)을 남긴다(변경 요청 상태 없음 — §3.5).

### ③ 외부 협력자 스코프 온보딩 — 초대 → 시크릿창 수락 → 제한 뷰 → 재-스코프 → 회수
1. **[김쿠아·owner]** 멤버 페이지 → 이메일·역할 `external_collaborator`·**범위=제품 하나(CO0100)** 초대 발급 → **링크 복사** → *로스터에 pending 초대* (§4.6)
2. **[시크릿 창]** 링크 열기 → "**<제품명>** 제품에 한정 참여합니다" → Google로 수락 → *대시보드에 **그 제품만** + 조상 브랜드명 무유출* (§5.1)
3. **[외부 협력자]** 타 제품 URL 직접 진입 → *권한 안내 후 루트로 리다이렉트(콘텐츠 미노출)* (§5.2)
4. **[김쿠아]** 로스터 행 인라인 **"+ 스코프"**로 두 번째 제품(CO0200) 직접 grant → *협력자는 재로그인 없이 즉시 두 제품 가시* (§5·§5.4)
5. **[김쿠아]** 스코프 배지 옆 **×**로 회수 → *협력자의 다음 요청에서 해당 제품 소멸(fail-closed·요청 간 stale 역할 없음)* (§5)

---

## 1. 준비

### 1-1. 실행 (두 가지 모드)

```bash
# 최초 1회: DB 준비 + 시드 + cooa_app 권한 부여 (owner 역할로)
COOA_DB_USER=$USER bin/rails db:prepare      # db:seed 자동 → 데모 org/계정/규제데이터
COOA_DB_USER=$USER bin/rails rls:grant_app   # structure.sql가 GRANT를 strip → cooa_app 권한 재적용(필수)

# 실행 (단일 모드 — 별도 인증앱·코드 입력 없음)
bin/dev
```

브라우저 → http://localhost:3000 → 미인증이면 `/session/new`(계정 피커, 비밀번호 없음)로 리다이렉트.

### 1-2. 페르소나 표 (db/seeds.rb 실측)

로그인은 `Account`(신원), 권한은 `RoleAssignment`(tenant-wide = 타입 스코프 미설정 · 제품 한정은 §5). 로그인 카드 순서 = `Account.id` 오름차순.

| 표시명 | 이메일 | 도메인역할 | 부여 role_key | 핵심 능력 |
|---|---|---|---|---|
| 김쿠아 | `kim@cooa.dev` | 디자이너 | **owner** + brand_admin | 전권(리뷰 요청·검토 확인·claim·담당자관리). **유일 owner** |
| 송쿠아 | `song@cooa.dev` | PM | brand_admin | 담당자/제품 관리 O · 리뷰 요청/검토 확인 **X** |
| 이쿠아 | `lee@cooa.dev` | RA | **ra_reviewer** + **approver** | 리뷰 요청 O · 검토 확인·claim O · 담당자관리 X (= 적격 리뷰어) |
| 박쿠아 | `park@cooa.dev` | SCM | contributor | 리뷰 요청 O · 검토 확인/claim **X** · 담당자관리 **X** (최소권한) |

> 검토 확인은 별도 코드 입력 없이 동작한다. 요청받은 담당자는 approve verb 없이도 확인 가능(소프트 게이트) — claim(미배정 자기배정)만 HARD approve verb를 요구.
> 시드에 순수 viewer/assignee 페르소나는 없음 — viewer 권한은 모든 페르소나의 기준선으로만 체감.

**역할→verb 매트릭스 핵심** (`app/policies/authz/permission_matrix.rb`, MATRIX_VERSION=1). 내부 verb 키 `approve`는 리뷰 모델에서 **검토 확인·claim 능력**을 가리킨다(ADR-002 §6 권한 상한 식별자 유지):
- `approve` → **owner, approver만** (= claim 적격 · 미지정 요청 확인 폴백)
- `submit_for_approval`(리뷰 요청) → contributor·ra_reviewer·owner 보유, **brand_admin엔 없음**
- `manage_members`/`manage_product` → **brand_admin, owner만**

### 1-3. 콘솔 두 모드 (RLS 때문에 갈림 — 중요)

| 명령 | 접속 역할 | 쓰임새 | 도메인 쿼리법 |
|---|---|---|---|
| `bin/rails console` | **cooa_app** (NOBYPASSRLS) | 정책/RLS/감사 체감 | 반드시 `TenantContext.with_tenant(...)`로 감싸야 행이 보임(미설정 시 0행=fail-closed) |
| `COOA_DB_USER=$USER bin/rails console` | **owner** (BYPASSRLS) | 계정/role 직접 조작 | 컨텍스트 없이 바로 조회/수정 |

데모 테넌트 id 상수: `TenantConfig::DEMO_TENANT_ID` (= `Organization.find_by(name: "COOA Demo").id`).

### 1-4. 버전 리뷰 패널 도달 경로 (③에서 반복 사용)

대시보드(`/`) → `레티놀 3% 세럼` → `일본(CO0001)` → 구성요소 `단상자(outer_box)` → 버전 **v5** → 버전 뷰(`/versions/:id`) 하단 **"버전 리뷰"** 패널. 리뷰는 버전에 앵커되어 **스크리닝과 무관하게** 요청/확인할 수 있다(디자이너는 스크리닝 없이 요청, RA는 필요 시 우상단 "인허가 스크리닝"(`versions/:id/screening`)을 검토 중 수행). 시드는 이 v5(JP)를 "리뷰 요청" 가능한 상태로 남겨 둠.

### 1-5. 범례

`[UI]` 화면 클릭 · `[콘솔]` rails console 복붙 · `[rake]` 정확한 rake 명령

---

## 2. 영역별 체크리스트

## ① 로그인 · 세션

### ☐ 1.1 계정 피커 로그인 + 페르소나 전환 `[UI]`
- **무엇** — 비밀번호 없이 데모 계정 선택만으로 로그인하고, 로그아웃 후 다른 페르소나로 재로그인해 권한 차이를 체감.
- **방법** — http://localhost:3000 → 카드 4개 중 **이쿠아 · RA · lee@cooa.dev** 클릭 → 대시보드. 로그아웃 → 다시 로그인 화면 → **박쿠아 · SCM** 재로그인.
- **확인** — 클릭 즉시 비번 없이 루트로 이동. 로그아웃 시 "로그아웃되었습니다." flash + `status: :see_other`. 카드 라벨이 페르소나 표와 정확히 일치.
- **메커니즘** — `SessionsController#new`가 `Account.active.includes(:user).order(:id)`를 뿌림. `#create`는 `reset_session`(세션 픽세이션 방어, ADR-003 §7.2) 후 `session[:account_id]`/`token_version` 적재. 로컬 로그인은 `config.x.local_login_enabled = !production`로 비-prod 한정.

### ☐ 1.2 세션 즉시 폐기 — token_version bump `[UI]`+`[콘솔]`
- **무엇** — 로그인 중 계정의 `token_version`을 올리면("전체 로그아웃"/역할변경/suspend의 공통 메커니즘) **다음 요청 한 번**에 즉시 강제 로그아웃.
- **방법** — 박쿠아로 로그인해 대시보드에 머문다. 별도 터미널:
  ```bash
  COOA_DB_USER=$USER bin/rails console
  ```
  ```ruby
  acc = Account.find_by(email: "park@cooa.dev")
  acc.token_version          # 현재 값 (예: 0)
  acc.bump_token_version!    # increment!(:token_version) → 1
  ```
  브라우저로 돌아가 아무 링크나 클릭.
- **확인** — 다음 요청에서 "로그인이 필요합니다." flash + `sessions/new`로 강제 리다이렉트. (bump 전 정상 → bump 직후 첫 요청에 끊김 = 즉시성).
- **메커니즘** — `Authentication#verify_revocation`가 매 요청 `Account.find_by(id:)`(의도적 unscoped) 재조회 후 `fresh.active? && fresh.token_version == session[:token_version]`이 아니면 `reset_session + require_login`. `bump_token_version!`은 ADR-003 §3.3 "revoke-all".

### ☐ 1.3 비-owner suspend → 강제 로그아웃 `[UI]`+`[콘솔]`
- **무엇** — `status="suspended"`로 바꾸면 라이브 세션이 다음 요청에 죽는다.
- **방법** — 박쿠아로 로그인해 머문다.
  ```ruby
  acc = Account.find_by(email: "park@cooa.dev")
  acc.update!(status: "suspended")   # 비-owner라 가드 통과
  ```
  브라우저에서 링크 클릭.
- **확인** — 다음 요청에서 "로그인이 필요합니다."로 강제 로그아웃 + `Account.active` 스코프에서 빠져 로그인 카드 목록에서 박쿠아 사라짐.
- **메커니즘** — `verify_revocation`의 `fresh.active?`(`status=="active"`) 체크 + `Account.scope :active`.

### ☐ 1.4 유휴 타임아웃 60분 `[콘솔]`(즉시)/`[UI]`(실측)
- **무엇** — 마지막 요청 후 60분 무활동이면 다음 요청에서 만료.
- **방법** — 상수 즉시 확인:
  ```bash
  COOA_DB_USER=$USER bin/rails runner 'puts Authentication::IDLE_TIMEOUT'   # => 3600
  ```
  실제 트리거: 로그인 후 60분 방치 → 클릭. (`last_seen`은 암호화 세션 쿠키 안 → 콘솔로 앞당길 수 없음. 코드 없이는 60분 대기가 정공법.)
- **확인** — 60분+ 유휴 후 첫 요청에서 "로그인이 필요합니다." 60분 이내 요청 1회면 `last_seen` 슬라이딩 갱신되어 리셋.
- **메커니즘** — `Authentication#resolve_account`가 매 요청 `session_expired?`(`Time.current - last_seen > IDLE_TIMEOUT`) 검사, 통과 시 `session[:last_seen]` 갱신. `IDLE_TIMEOUT = 60.minutes`.

---

## ② 권한 매트릭스 UI 체감 (SoD)

### ☐ 2.1 페르소나별 버튼 가시성 `[UI · 전환]`
- **무엇** — 같은 화면이라도 로그인 역할에 따라 액션 버튼이 조건부로 나타난다(SoD를 화면에서 체감).
- **방법** — `bin/dev` → 1-4의 버전 리뷰 패널 진입 → **"리뷰 요청"** 버튼을 각 페르소나로 관찰:

  | 페르소나 | "리뷰 요청" |
  |---|---|
  | 박쿠아(contributor) | 보임 |
  | 이쿠아(ra+approver) | 보임 |
  | 김쿠아(owner) | 보임 |
  | 송쿠아(brand_admin) | **"리뷰 요청 권한이 없습니다."** 텍스트로 대체 |
- **확인** — 송쿠아만 버튼 부재. 이어 제품 드로어 → **담당자** 편집 → 저장: 송/김 성공, 박/이 **403**.
- **메커니즘** — 뷰의 `policy(@version).submit_for_approval?` 조건부 렌더(`_review_panel.html.erb`) + `ApplicationPolicy#can?`가 `roles_on(record) ∩ MATRIX(verb)` 교집합으로 판정. 담당자는 뷰에서 숨기지 않고 컨트롤러가 막음: `ProductsController#update`의 `authorize @product, :manage_members? if params[:members].present?`.

### ☐ 2.2 직접 POST 우회 → 403 `[UI · devtools]` 또는 `[콘솔]`
- **무엇** — 버튼이 없어도, 권한 없는 페르소나가 검토 확인 POST를 직접 쏴도 서버가 거부.
- **방법** — (선행) 박쿠아로 **리뷰 요청** 클릭(pending 생성). 송쿠아로 로그인 → DevTools 콘솔:
  ```js
  fetch('/approval_requests/REQ_ID/confirm', {
    method: 'POST',
    headers: { 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content },
  }).then(r => console.log(r.status));   // => 403
  ```
  대안 `[콘솔]`(정책만 검증):
  ```ruby
  TenantContext.with_tenant(TenantConfig::DEMO_TENANT_ID) do
    song = Account.joins(:user).find_by(users: { email: "song@cooa.dev" })
    req  = ApprovalRequest.order(:id).last
    ctx  = Authz::AccessContext.new(actor: song)
    pp ApprovalRequestPolicy.new(ctx, req).confirm_review?   # => false
  end
  ```
- **확인** — HTTP **403**(`head :forbidden`), `log/development.log`에 `[authz][deny] verb=confirm_review?`, audit_logs에 outcome=deny 1행.
- **메커니즘** — 모든 mutation은 `after_action :verify_authorized` 강제. 거부 시 `Pundit::NotAuthorizedError` → `deny_access`가 비-GET엔 `head :forbidden` + `audit_deny`가 별도 테넌트 tx로 deny 기록(`application_controller.rb`).

---

## ③ 버전 리뷰 워크플로 (핵심)

> 대상 고정: **CO0001 / 일본 / 단상자 / v5** (owner=김쿠아). 리뷰는 버전에 앵커 — 스크리닝 비의존.
> id 헬퍼 `[콘솔]`:
> ```ruby
> TenantContext.with_tenant(TenantConfig::DEMO_TENANT_ID) do
>   cv = Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box").component_versions.find_by(version_number: 5)
>   cv.id   # /versions/<cv.id> 하단 "버전 리뷰" 패널
> end
> ```

### ☐ 3.1 리뷰 요청 → pending `[UI]`
- **무엇** — 버전 리뷰 패널에서 "리뷰 요청"하면 `approval_request` 1건 생성 + 콘텐츠 스냅샷(검토튜플) 캡처. 담당자를 리뷰어로 지정할 수도, 미지정으로 둘 수도 있다.
- **방법** — 김쿠아로 버전 뷰(1-4) → "버전 리뷰" 패널 → (선택) 담당자 체크 → **"리뷰 요청"** 클릭.
- **확인** — 패널이 **"리뷰 대기 / 요청됨"**(주황) + "요청자 김쿠아". 플래시 = 지정 시 "…님에게 리뷰를 요청했습니다.", 미지정 시 "리뷰 요청이 제출되었습니다 — 리뷰어를 지정하지 않아 자격 리뷰어 누구나 확인할 수 있습니다."
- **메커니즘** — `POST /approval_requests?component_version_id=` → `authorize cv, :submit_for_approval?` → `ApprovalRequest.submit_for!`가 `ReviewedTuple.capture`(라벨텍스트·성분·아트워크·verdict·룰셋버전 해시) 후 status `pending`. 전이는 원자 tx + `audit_log`(action `submit_for_approval`) 1행.

### ☐ 3.2 M1 — 적격 리뷰어 0 → 소프트 "리뷰어 미배정" 안내(하드 차단 아님) `[콘솔]`+`[UI]`
- **무엇** — 테넌트에 "요청자와 구별되는" 검토 자격 신원이 0이어도 요청은 **여전히 pending**으로 생성된다(리프레임: 하드 차단 폐지). UI는 소프트 안내만 띄운다.
- **방법** — owner(김쿠아)는 요청자라 자동 제외 → 이쿠아의 approver만 빼면 적격자 0:
  ```ruby
  TenantContext.with_tenant(TenantConfig::DEMO_TENANT_ID) do
    lee_id = User.find_by(email: "lee@cooa.dev").id
    RoleAssignment.where(role_key: "approver").joins(:account)
                  .where(accounts: { user_id: lee_id }).destroy_all
  end
  ```
  김쿠아로 리뷰어 미지정 **"리뷰 요청"**.
- **확인** — 플래시 **"리뷰 요청됨 — 아직 검토 가능한 구성원(요청자와 다른 리뷰어)이 없습니다."** (하드 차단·빨간 박스 없음. 복구: `COOA_DB_USER=$USER bin/rails db:seed`).
- **메커니즘** — 컨트롤러 `submit_notice`가 `EligibleApproverService.any?(exclude_user_id: req.submitter_id)`로 분기(시장관할 필터 없음). 적격 = tenant-wide `RoleAssignment.active.where(role_key: %w[owner approver])` − 제출자. brand_admin·contributor는 적격 아님.

### ☐ 3.3 SoD — 본인 요청 건 본인 확인 불가 `[UI · 전환]`
- **무엇** — 검토 verb 보유자라도(owner 포함) 자신이 요청한 리뷰는 확인 불가.
- **방법** — 김쿠아(owner)가 요청해 pending인 패널을 김쿠아로 본다 → 확인 버튼 없음 + 회색 **"본인이 요청한 리뷰는 본인이 확인할 수 없습니다 (SoD)."** → 이쿠아(approver)로 전환 → 같은 버전 뷰 재방문 → **"✓ 검토 확인"** 버튼 등장 → 클릭.
- **확인** — 김쿠아: SoD 문구. 이쿠아: 확인 후 초록 **"✓ 검토 확인됨 · 이쿠아 · 시각"**, 플래시 "검토 확인되었습니다."
- **메커니즘** — `ApprovalRequestPolicy#confirm_review? = reviewer_capable?(:approve) && record.pending? && actor_present? && submitter_distinct?`. `reviewer_capable?` = 요청받은 리뷰어 OR `can?(:approve)`(소프트 게이트 — 지정 담당자는 verb 없어도 확인 가능) · `submitter_distinct?`가 SoD(요청자≠확인자, **owner 예외 없음**). `actor_id`는 도메인 User bigint 브리지(`access_context.rb`).

### ☐ 3.4 stale — 요청 후 검토대상 변경 → 확인 차단 `[UI/콘솔]`
- **무엇** — 요청 시점에 캡처한 내용(라벨텍스트·성분·아트워크·verdict)이 그 후 바뀌면 확인 순간 재검증에서 막힌다. pending 유지 + deny 감사(TOCTOU 방어).
- **방법** — 먼저 3.1로 pending 생성. 검토대상 변경:
  - `[UI]` `/versions/:id/edit`("버전 수정")에서 **아트워크 재업로드** → `artifact_digest` 변경.
  - `[콘솔]` label_text 편집:
    ```ruby
    TenantContext.with_tenant(TenantConfig::DEMO_TENANT_ID) do
      cv.label_texts.find_by(text_type: "label").update!(content: "STALE TEST EDIT")
    end
    ```
  이쿠아로 전환 → **"✓ 검토 확인"** 클릭.
- **확인** — 빨간 플래시 **"검토 내용이 변경되어 확인할 수 없습니다. 변경 내용을 다시 검토하세요."** 패널은 여전히 pending. 감사 deny 1행:
  ```ruby
  AuditLog.where(resource_type: "ApprovalRequest", outcome: "deny").order(:id).last
  # action="confirm_review", denial_reason="stale_reviewed_tuple"
  ```
- **메커니즘** — `ApprovalRequest#confirm_review!`가 tx에서 `component_version.lock!`(FOR UPDATE)로 직렬화 후 `ReviewedTuple.stale?`(라이브 content/artifact/verdict/버전 vs 캡처값) → 불일치면 `raise StaleReviewedTuple`. 컨트롤러 rescue → `audit_stale` + redirect, status는 pending 유지.
  > 정직 노트: label_text 직접 편집 UI는 없음(버전 수정 폼은 `change_reason/current/artwork`만 permit). 순수 UI로는 아트워크 재업로드로 staleness 재현.

### ☐ 3.5 claim(미배정 자기배정) + 피드백 채널 `[UI]`
- **무엇** — "고쳐야 함"은 별도 상태(반려)가 아니라 **피드백**(annotation)이다. 그리고 리뷰어 미지정 요청은 적격자가 인박스에서 **자기배정(claim)**해 맡는다("변경 요청/반려" 상태 폐지).
- **방법** — (claim) 박쿠아로 미지정 **"리뷰 요청"** → 이쿠아로 사이드바 **"내 리뷰 인박스"**(`/reviews`) → "리뷰어 미배정"(Segment B)의 카드 **"내가 맡기"** → "내게 요청된 리뷰"(Segment A)로 이동 + 배지 +1. (피드백) 버전 뷰 아트워크에서 **Shift+드래그**로 코멘트를 남기면 요청자가 반영, 리뷰어가 **반영 확인(resolve)**.
- **확인** — claim 후 인박스 A에 등장·B에서 소멸·플래시 "리뷰를 맡았습니다 …". 미해결 피드백이 있으면 pending 패널에 **"미해결 피드백 N개 — 반영 후 재요청하거나, 리뷰어가 검토 확인합니다."**
- **메커니즘** — `POST /approval_requests/:id/claim` → `ApprovalRequestPolicy#claim? = can?(:approve) && pending? && actor_present? && submitter_distinct? && requested_reviewer_ids.none?`(HARD approve verb + 미배정만). `add_reviewer!`의 유니크 백스톱을 컨트롤러가 SAVEPOINT(`requires_new`)로 격리해 동시 claim을 멱등 처리.

### ☐ 3.6 버전 리뷰 패널 상태 한눈 매핑 (참고, `_review_panel.html.erb`)

| 상태 | 화면 |
|---|---|
| 요청 전 + 요청권한 O | 그라데이션 **"리뷰 요청"**(+ 담당자 리뷰어 지정 체크박스) |
| 요청 전 + 권한 X | 회색 **"리뷰 요청 권한이 없습니다."** |
| pending + 확인가능 | **"리뷰 대기/요청됨"** + **"✓ 검토 확인"** 버튼 |
| pending + 요청본인 | **"본인이 요청한 리뷰는 본인이 확인할 수 없습니다 (SoD)."** |
| pending + 무자격 타인 | 대기 안내(`waiting_message`) |
| pending + 미해결 피드백 | 분홍 **"미해결 피드백 N개 — …"** |
| reviewed | 초록 **"✓ 검토 확인됨 · 이름 · 시각"** |

---

## ⑤ last-owner 가드 (가용성)

### ☐ 5.1 유일 owner 정지/삭제/강등 거부 `[콘솔]`
- **무엇** — 테넌트엔 항상 active owner 최소 1명이 남아야 한다. 유일 owner(김쿠아)를 정지·삭제·owner 제거 시도하면 거부 + 롤백.
- **방법** — `COOA_DB_USER=$USER bin/rails console`:
  ```ruby
  Current.tenant_id = TenantConfig::DEMO_TENANT_ID
  kim = Account.find_by(email: "kim@cooa.dev")
  kim.update!(status: "suspended")   # ① 정지
  kim.destroy!                       # ② 삭제
  kim.role_assignments.active.tenant_wide.find_by(role_key: "owner").destroy!  # ③ 강등
  ```
  대조: 송쿠아에게 owner 부여 후 ①을 다시 하면 **성공**(다른 active owner 존재).
  ```ruby
  RoleAssignment.create!(account: Account.find_by(email: "song@cooa.dev"),
    tenant_id: Current.tenant_id, role_key: "owner", scope_type: "tenant")
  ```
- **확인** — ①②③ 모두 `LastOwnerGuard::Error: 마지막 owner는 정지·강등·제거할 수 없습니다 (테넌트에 active owner가 최소 1명 남아야 합니다).` 대조 실험에선 ①이 성공.
- **메커니즘** — 단일 진입점이 없어 **모델 인바리언트**로 구현: `Account`의 `before_update :guard_last_owner_on_deactivate`/`before_destroy`, `RoleAssignment`의 `before_destroy :guard_last_owner`/`before_update :guard_last_owner_on_expire`가 모두 `LastOwnerGuard.ensure_owner_remains!` 호출. 내부에서 `pg_advisory_xact_lock`(NS `0x4C4F`)로 동시 강등 직렬화 후 `other_active_owners?` 없으면 raise.

---

## ⑥ RLS 테넌트 격리

> 데모는 단일 테넌트라 교차 격리는 **콘솔에서 임의 테넌트 컨텍스트**로 체험(별도 org 생성 불필요).

### ☐ 6.1 교차 테넌트 0행 (fail-CLOSED) `[콘솔]`
- **무엇** — 다른 테넌트 컨텍스트로 같은 테이블을 읽으면 한 행도 안 보인다.
- **방법** — `bin/rails console` (cooa_app):
  ```ruby
  TenantContext.with_tenant(TenantConfig::DEMO_TENANT_ID) { Product.count }   # => 양수(시드 노드)
  TenantContext.with_tenant(SecureRandom.uuid)           { Product.count }   # => 0 (교차 격리)
  Product.count                                                              # => 0 (컨텍스트 미설정=fail-CLOSED)
  ```
- **확인** — 첫 줄만 양수, 나머지 **0**. `rls_app_connection_test.rb`의 "no tenant context → SELECT is fail-CLOSED" 스모크와 동일 보장.
- **메커니즘** — `TenantContext.with_tenant`가 tx 안에서 `SELECT set_config('app.current_tenant_id', …, true)`(SET LOCAL)로 GUC 설정, RLS 정책이 이를 읽음. 미설정 시 `NULLIF→NULL` 매칭 0행.

### ☐ 6.2 RLS 자세 점검 rake `[rake]`
- **무엇** — 모든 테넌트 테이블이 ENABLE+FORCE+정책을 갖췄고, append-only 테이블에 cooa_app UPDATE/DELETE가 없음을 한 번에 감사.
- **방법** — `COOA_DB_USER=$USER bin/rails rls:audit`
- **확인** — `RLS audit OK — N tenant-scoped table(s) ENABLE+FORCE+policy (exempt: …)` + `Append-only OK — 1 table(s): no cooa_app UPDATE/DELETE + trigger.` 결함 시 누락 테이블명과 `abort`.
- **메커니즘** — `pg_class.relrowsecurity/relforcerowsecurity` + `pg_policies`로 누락 검출, `information_schema.role_table_grants`로 cooa_app UPDATE/DELETE 누수 검사, `pg_trigger`로 불변성 트리거 확인(`lib/tasks/cooa.rake`).

---

## ⑦ 감사 무결성

### ☐ 7.1 audit_logs는 append-only — cooa_app UPDATE/DELETE 거부 `[콘솔]`
- **무엇** — 감사 로그는 추가만 가능. 앱 역할(cooa_app)의 수정/삭제를 DB가 거부.
- **방법** — `bin/rails console`(cooa_app):
  ```ruby
  TenantContext.with_tenant(TenantConfig::DEMO_TENANT_ID) do
    AuditLog.where(outcome: "deny").limit(1).update_all(action: "tampered")   # UPDATE
  end
  # 동일하게 ... .delete_all → DELETE
  ```
- **확인** — 둘 다 `ActiveRecord::StatementInvalid`(`PG::RaiseException: audit_logs is append-only (UPDATE/DELETE blocked)` 또는 `InsufficientPrivilege`). 반면 ②/③의 deny 흐름에서 INSERT는 성공해 행이 남음.
- **메커니즘** — cooa_app에 `SELECT, INSERT`만 부여(`APPEND_ONLY_TABLES`), UPDATE/DELETE 미부여 + `structure.sql`의 트리거 `audit_logs_no_mutate`(`BEFORE DELETE OR UPDATE … RAISE EXCEPTION`). INSERT조차 RLS WITH CHECK로 테넌트 GUC 필요 → deny 기록 시 `deny_access`가 새 `TenantContext.with_tenant`로 GUC 재설정 후 기록.

### ☐ 7.2 해시체인 검증 + BOLA 탐지 `[rake]`+`[콘솔]`
- **무엇** — 감사 로그는 테넌트별 해시체인. 갭/변조/삭제 검출, deny 폭주(BOLA 정황) 탐지.
- **방법** —
  ```bash
  COOA_DB_USER=$USER bin/rails audit:verify
  COOA_DB_USER=$USER MINUTES=5 THRESHOLD=10 bin/rails audit:detect_bola
  ```
  한 행 들여다보기 `[콘솔]`:
  ```ruby
  Current.tenant_id = TenantConfig::DEMO_TENANT_ID
  a    = AuditLog.where(tenant_id: Current.tenant_id).order(:tenant_seq).last
  prev = AuditLog.where(tenant_id: a.tenant_id, tenant_seq: a.tenant_seq - 1).first
  a.prev_chain_hash == prev.chain_hash      # => true (앞 행과 연결)
  a.chain_hash == a.expected_chain_hash     # => true (본문 재계산 일치)
  ```
- **확인** — `audit:verify OK — N row(s)… chains intact.`(갭/변조 시 `FAILED`로 abort). `detect_bola OK — no actor exceeded 10 denies in 5m.` (②③에서 deny를 여러 번 만들면 잡힘). 해시 비교 두 줄 모두 `true`.
- **메커니즘** — `AuditLog`의 `before_create :assign_chain`이 `pg_advisory_xact_lock`(NS `0x4155`) 아래 `tenant_seq` 증가 · `prev_chain_hash = 직전 chain_hash` · `chain_hash = AuditLogHash.compute(...)` 채움. `audit:verify`는 행마다 seq gap·prev 끊김·재계산 불일치 검사, 소유자 역할로 RLS 우회해 전 테넌트 순회.

---

## 3. 요약 — 이 체크리스트가 증명하는 보장

| 보장 축 | 증명 항목 | 한 줄 |
|---|---|---|
| **격리 (Isolation)** | ⑥ 6.1, 6.2 / ⑦ 7.1 | RLS FORCE + GUC, 컨텍스트 없으면 fail-CLOSED(0행) |
| **인증 (AuthN)** | ① 1.1~1.4 | account-picker + 매 요청 token_version/idle 폐기, 픽세이션 방어 |
| **인가 (AuthZ)** | ② 2.1, 2.2 / ③ 3.6 / 1-2매트릭스 | role→verb 매트릭스 교집합, 뷰 숨김 + 서버 403(verify_authorized) |
| **직무분리 (SoD)** | ③ 3.3 (M2) / ② 2.1 | 요청자 ≠ 확인자 강제, owner 예외 없음 |
| **스코프 격리 (Scoping)** | §4.6 / §5.1~5.4 | 제품-한정 grant·초대 — 서브트리만 가시·조상 브랜드명 무유출, 타 제품 fail-closed |
| **가용성 (Availability)** | ⑤ 5.1 / ③ 3.2 (M1) | last-owner 가드, 적격 리뷰어 0이면 소프트 안내(하드 차단 폐지) |
| **감사 (Audit/Integrity)** | ⑦ 7.1, 7.2 / ② 2.2 | append-only 트리거 + 해시체인 verify + BOLA 탐지 |

### 추천 진행 순서
1. `bin/dev` → ① 로그인/전환 → ② 버튼 가시성 → ③ 박 리뷰 요청·이/김 검토 확인·claim·SoD·stale·피드백.
2. §4 Google 초대(제품-스코프 §4.6 포함) · §5 스코프 격리(최디자) 브라우저 검증.
3. `COOA_DB_USER=$USER bin/rails console` → ⑤ owner 가드 3종 → ⑥ 격리 3-라이너 → ⑦ audit UPDATE/DELETE 거부.
4. `COOA_DB_USER=$USER bin/rails rls:audit` & `audit:verify` & `audit:detect_bola`.

---

## 4. Google 소셜 로그인 · 조직 초대 수동 검증 (2026-07-02 · Phase 2/3)

> 자동화 불가 영역: 실 Google 계정 왕복은 mock으로 검증 불가(통합 매트릭스 23종은 test_mode로 커버됨).
> 아래는 **사용자 1회 셋업 + 5개 검증 항목**.

### ☐ 4.0 셋업 (1회)
> **콘솔 들어가기 전 실행**: `bin/rails auth:google_preflight` — 콘솔에 붙여넣을 **정확한 리디렉션 URI** 출력 + env/gem 준비 상태 확인(전 환경 안전).

1. [Google Cloud Console](https://console.cloud.google.com/apis/credentials) → OAuth 동의 화면(External, scope: email/profile/openid) 구성.
2. 사용자 인증 정보 → **OAuth 클라이언트 ID 생성**(유형: 웹 애플리케이션) → 승인된 리디렉션 URI에 preflight가 출력한 값(`http://localhost:3000/auth/google_oauth2/callback`) 추가.
3. bin/dev를 띄우는 셸에서: `export GOOGLE_CLIENT_ID=<client-id>` · `export GOOGLE_CLIENT_SECRET=<secret>` → `bin/dev` 재기동.
4. `bin/rails auth:google_preflight`로 "✓ 앱 측 준비 완료" 확인 + 로그인 페이지에 "Google로 로그인" 버튼 확인.

> **가장 쉬운 첫 테스트 = §4.2 초대 플로우(rails 콘솔 0)**. 직접 로그인(§4.1)만 시드 계정 정렬이 필요하며 그것도 rake로 처리.
> dev 환경에선 로그인 거부 시 브라우저에 **구체 사유**가 표시된다(예: "매칭 계정 없음 — auth:link_google 실행"). 프로덕션은 generic 유지.

### ☐ 4.1 (선택) 직접 로그인 — 기존 멤버가 Google로 `[브라우저]`
`bin/rails auth:link_google[<본인@gmail>]`(dev 전용 — owner kim 계정을 내 Gmail로 정렬) → "Google로 로그인" → 대시보드 진입(owner 권한) + 재로그인도 성공(재방문 매칭). 원복: `bin/rails auth:unlink_google`.

### ☐ 4.2 초대 → 수락 (핵심 저니) `[브라우저 2개]`
김쿠아(owner)로 멤버 페이지 → 다른 본인 이메일로 초대 생성 → **링크 복사** → 시크릿 창에서 링크 열기 → "OO 조직에 초대되었습니다" → Google로 계속 → 해당 Google 계정으로 로그인 → 대시보드 진입 · 멤버 페이지에 새 멤버 등재(역할 칩 확인).

### ☐ 4.3 티켓 재사용 거부 `[시크릿 창]`
같은 초대 링크를 다시 열면 "유효하지 않은 초대" · 다른 Google 계정으로 수락 시도해도 거부.

### ☐ 4.4 미초대 Google 계정 거부 `[시크릿 창]`
초대 없는 임의 Google 계정으로 "Google로 로그인" → "허가되지 않은 계정입니다"(계정 미생성).

### ☐ 4.5 초대 취소 `[브라우저]`
초대 생성 → 취소 → 링크 열면 무효 · audit_logs에 invitation.create/revoke 기록(`AuditLog.where("action LIKE 'invitation%'")`).

### ☐ 4.6 제품-스코프 초대 → 제한된 멤버 `[브라우저 2개]` — Stage 3
김쿠아(owner)로 멤버 페이지 → 초대 폼에서 이메일·역할(`external_collaborator`)·**범위=제품 하나**(예: CO0100)
선택 → 초대 생성 → **링크 복사** → 시크릿 창에서 열기 → 랜딩에 "**<제품명>** 제품에 한정 참여합니다" 표시 →
Google로 수락 → 대시보드에 **그 제품만** 보이고(조상 브랜드명 무유출·§5.1과 동일) 타 제품 진입 차단(§5.2).
멤버 로스터에 해당 계정이 **`external_collaborator @ <제품명>` 스코프 배지**로 등재 · 배지 옆 **×**로 회수 ·
행 인라인 **"+ 스코프"**로 두 번째 제품 추가 → 재로그인 없이 즉시 가시. audit_logs에 `invitation.create`(scope
포함)·`invitation.accept`·`role_assignment.grant`/`revoke` 기록.

## 5. 스코프 grant (제품 한정 접근) 검증 — Stage 2 `[브라우저]`

역할 부여가 **테넌트 전역이 아니라 제품 하나에만** 묶였을 때(external_collaborator), 그 신원이 해당 제품
서브트리만 보고 그 밖은 접근조차 못 하는지 확인한다. 시드에 검증용 신원 **최디자(choi@partner.example —
CO0200 제품 한정)** 가 이미 있으므로 콘솔 0으로 시작 가능.

> ✅ **Stage 3 반영.** 외부 협력자를 **제품-스코프 초대**로 직접 온보딩할 수 있다(§4.6). 초대 폼의 "범위"에서
> 제품을 고르면 수락 시 그 제품 서브트리 한정 `external_collaborator` grant가 생성된다(**tenant-wide 아님** —
> 전 테넌트 유출 없음). `scope_product_id`/`scope_component_id`는 **테넌트 소속 검증**(RLS로 교차-테넌트·미존재는
> 불가시 → 거부)을 초대·직접 grant 양 경로가 공유한다.
>
> 📌 **이메일당 pending 초대는 1건**(부분 유니크). 한 계정을 **여러 제품**에 스코프하려면 초대 수락 후
> **직접 grant**로 추가한다 — 멤버 로스터의 행 인라인 **"+ 스코프"** 폼(제품 선택) 또는 §5.4 콘솔 레시피.

### ☐ 5.1 스코프 신원 로그인 → 제한된 트리 `[브라우저]`
계정 픽커에서 **최디자**로 로그인 → 대시보드/사이드바에 **CO0200(미국·시카 수딩 크림 SKU)만** 보임.
다른 브랜드(레티놀 3% 세럼·비타민C 브라이트닝 앰플)와 **조상 브랜드명("시카 수딩 크림")은 트리 노드로
렌더되지 않음**(재루팅으로 브랜드명 유출 차단). CO0200은 최상위(display root)로 올라와 보인다.
CO0200 행/이름을 클릭해 드로어를 열면 상단 **"경로"가 `미국`만** 표시되고(권한 없는 상위 브랜드명
`시카 수딩 크림`은 브레드크럼·경로에 노출 안 됨). 대조로 tenant-wide 신원(김·이)이 같은 SKU를 열면 경로가
`시카 수딩 크림 › 미국` 전체로 보인다.

### ☐ 5.2 타 제품 직접 URL 차단 `[브라우저]`
최디자 상태에서 타 제품의 상세를 직접 주소로 진입(`/products/<CO0001 id>`) → 콘텐츠 미노출(권한 안내 후
루트로 리다이렉트). 타 제품 버전(`/versions/<id>`)도 동일. 변이(예: 타 제품에 구성요소 추가 POST)는 403.

### ☐ 5.3 리뷰 인박스 Segment B 미노출 `[브라우저]`
최디자로 `/reviews` → "리뷰어 미배정 — 내가 맡을 수 있는 리뷰"(Segment B) 섹션이 **아예 없음**
(external_collaborator는 적격 리뷰어가 아님). owner/approver(김·이)로 로그인하면 Segment B가 보인다(대조).

### ☐ 5.4 (참고) 콘솔에서 product-scope grant 만들기 `[rails console]`
```ruby
acc  = Account.find_by!(email: "<협력자 이메일>")        # 초대 대신 사전 생성된 계정
prod = Product.find_by!(code: "CO0200")                  # 부여할 제품(리프 SKU 권장)
RoleAssignment.create!(account: acc, tenant_id: acc.tenant_id,
                       role_key: "external_collaborator", scope_type: "product",
                       scope_product_id: prod.id)         # component 한정이면 scope_type:"component"+scope_component_id
```
owner는 스코프 부여 불가(모델 검증 `owner grants must be tenant-wide`) · 부여 대상 제품/구성요소 삭제 시
grant는 FK cascade로 자동 정리된다.
