# 에러 핸들링 규약 (E1–E8)

> **왜 이 문서가 있나.** 에러 처리가 컨트롤러마다 제각각이면(어디선 500 표면화, 어디선 무음 redirect,
> 어디선 head 403) 사용자는 깨진 화면을, 운영자는 은폐된 결함을 만난다. 이 문서는 COOA 웹앱의 **단일
> 에러 표면 규약**을 못박는다. 신규 컨트롤러·서비스·잡·프론트는 여기를 따른다(dev-discipline R9).

---

## 1. 인가 거부(deny) 규약 — 불변(ADR-002 §5.4)

`ApplicationController#deny_access`(`Pundit::NotAuthorizedError` rescue):
- **GET + html** → `redirect_to root_path, alert: "권한이 없습니다.", status: :see_other`(303).
- **그 외(mutation·비html)** → `head :forbidden`(403). 앤티-이늄(다른 테넌트 행은 RLS가 이미 404).
- **감사**: `audit_deny`가 fresh tenant tx에서 deny 1행 기록(best-effort — 감사 실패가 clean 403을
  500으로 바꾸지 않는다). deny 급증 = BOLA 신호(`audit:detect_bola`).

이 경로는 우수·안정 — E-트랙에서 변경하지 않았다.

## 2. 전역 rescue 계층 (E1)

`ApplicationController`:

| 예외 | 상태 | html | 비html(JSON/Turbo Stream) |
|---|---|---|---|
| `ActiveRecord::RecordNotFound` | 404 | `public/404.html` 파일 렌더(layout 없음) | `head :not_found` |
| `ActionController::ParameterMissing` | 400 | `public/400.html` | `head :bad_request` |

- **`RecordInvalid`는 전역 rescue하지 않는다.** 폼마다 표준이 다르기 때문(§3). 전역으로 422를 뿌리면
  인라인 검증 피드백·flash 안내를 덮어써 UX가 퇴화한다.
- 컨트롤러 레벨 rescue라 **환경 무관 일관**(middleware `show_exceptions` 설정에 의존하지 않음).
- 정적 에러 페이지(`public/*.html`)는 **한글 카피·COOA 토큰 인라인 CSS**(asset 파이프라인 무의존) —
  404/422/500/400. `RoutingError`(미존재 경로)는 컨트롤러 밖이라 여전히 middleware가 같은 파일을 서빙.

## 3. 폼 에러 표준 (E3) — 무엇을 쓰나

| 맥락 | 규약 | 근거·예시 |
|---|---|---|
| 파일 업로드/대형 폼 | **인라인 422 재렌더** | 검증 메시지를 필드 옆에. `component_versions#create`(artwork 검증) 패턴. |
| PRG 소형 폼(인라인 rename·담당자·트리 CRUD·피드백) | **flash alert + redirect_back** | `@record.errors.full_messages.to_sentence`. `products#create/update`·`components#update`(인라인 rename·이름 길이 200)·`annotations`·`annotation_comments`. |
| 고정값·서버계산이라 실패 불가에 가까움 | **bang 유지(표면화)** | `components#create`(고정 이름). 실패=버그 → 500/422로 표면화. |
| 멱등(동시·더블클릭) | **rescue `RecordNotUnique` → 안내 notice** | `invitations`·`role_assignments`·`approval_requests#claim`. `Rails.logger.info` 1줄. |

- **bang(`create!`/`update!`) 기준**: "present/타입 가드를 이미 통과했고 검증 실패 = 코드버그"일 때만.
  그 외 사용자 입력 검증은 non-bang + 위 표.
- 서비스 내부 tx의 `create!`(예: `ScreeningService#run!`)는 서비스에 유지하고, **호출부**가
  `rescue ActiveRecord::RecordInvalid → flash`로 안내(`screenings#run_screening`).

## 4. 도메인 액터 가드 (E4)

감사(allow)를 남기거나 User FK(`*_by_id`/`author`)를 쓰는 도메인 쓰기는 **연결 User가 있는 계정만** 수행.
`ApplicationController#require_domain_actor`(`current_account&.user_id`가 없으면 `head :forbidden`)를
`before_action`으로 적용: `invitations#create/destroy`·`role_assignments#create/destroy`·
`approval_requests#create/claim`·`annotations#create/resolve/reopen`·`annotation_comments#create`. 미브리지
계정이 `AuditLog.record!`의 fail-closed raise(500) 또는 NOT NULL author(annotation_comments)에 닿기 전에 fail-closed 403으로 막는다
(의미 불변). `before_action` halt 시 `after_action :verify_authorized`는 실행되지 않는다.

## 5. 서비스 실패 신호 — 3규약 (언제 무엇을)

| 신호 | 의미 | 사용처 | 선택 기준 |
|---|---|---|---|
| **nil 반환** | "해당 없음/조용한 실패" | `InvitationAcceptance`(수락 불가 시 nil) | 호출부가 nil을 자연스럽게 분기하고 실패가 예외적이지 않을 때. |
| **Result 구조체** | 성공/실패 + 페이로드 | `PdfProbe.check`(`ok`/`error`)·`ScreeningService#call`(`decision`/`findings`/`summary`) | 실패에 **구조화된 사유·데이터**(메시지·판정)가 필요할 때. |
| **예외 raise** | "여기서 멈춰야 함(불변식 위반)" | `LastOwnerGuard`·`ApprovalRequest::StaleReviewedTuple`·`AuditLog`(actor nil) | 계속 진행이 위험해 호출부가 tx 롤백/명시 rescue를 해야 할 때. |

원칙: **한 서비스는 한 규약만**. 규약을 바꾸면 호출부 전부를 함께 바꾼다.

## 6. 잡 정책 (E6)

`ApplicationJob`:
- `retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3` — **일시 오류만** 재시도.
- ActiveStorage 오류(체크섬/포맷/preview)는 **재시도 안 함**(결정적 실패 → 표면화·`failed_executions` 적재).
- `discard_on ActiveJob::DeserializationError` — 사라진 레코드 참조 잡은 폐기.
- `StandardError` 전반 retry 금지(비멱등 잡의 중복 부작용). 관측면: `solid_queue_failed_executions`
  (prod-cutover §12 모니터링).

## 7. 프론트 실패 토스트 (E5)

`controllers/lib/net_error_toast.js`:
- 전역 리스너 `turbo:fetch-request-error`·`turbo:frame-missing` → 토스트("네트워크 오류 — 잠시 후 다시
  시도해주세요", `role=alert`, 수동 닫기). 레이아웃 flash와 동일 결(warn/tint/ink 토큰, 인라인 스타일).
- 수동 `fetch`의 **catch(네트워크 실패) 경로**에서 `showNetErrorToast()` 직접 호출: `tree_dnd`·`sortable`
  (무음 reload 직전). 서버 거부(`!res.ok`/422)는 토스트 없이 서버 상태로 재동기(정상 리컨실 — 네트워크
  오류가 아니므로 이 메시지를 띄우지 않는다).

## 8. 관측 (E7)

- `config/initializers/error_reporting.rb` — `Rails.error.subscribe`로 보고 예외를 `[error_report]` 한 줄
  구조화 로그(class·message·handled·severity·source·controller#action·request_id·tenant). **PII 금지**.
- controller/action/request_id는 Rails가 error 컨텍스트에 실어주는 **컨트롤러 인스턴스**(`context[:controller]`)에서
  파생한다 — 예약 키 `:controller`/`:action`을 `set_context`로 덮어쓰면 Rails 내부가 String에 `.action_name`을
  호출하다 깨진다(dev 전용 회귀 — button_to per-form CSRF에서 표면화, `bin/smoke`가 포착).
- **배포 시** 이 initializer가 Sentry 등 외부 리포터/APM 연결 지점(DSN). 현재는 로그만.
- 멱등 rescue·삼킨 실패는 `Rails.logger.info` / `Rails.error.report(handled: true)`로 **조용히 사라지지
  않게** 남긴다.
