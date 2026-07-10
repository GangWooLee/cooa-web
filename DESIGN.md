# COOA 디자인 시스템 (DESIGN.md)

> 디자인 리뷰·구현의 **캘리브레이션 기준**. 이 문서 위반 = 높은 심각도.
> 원천: `app/assets/tailwind/application.css`(토큰) + `app/helpers/ui_helper.rb`(컴포넌트) — 값이 충돌하면 코드가 진실, 이 문서를 갱신한다.
> 에러/폼 표면 규약은 `docs/error-handling.md`(E1~E8)가 별도 진실원천.

## 0. 원칙

1. **기본기 우선**: 화려함보다 위계·정렬·간격·상태의 일관성. 사용자가 불편 없이 depth 5까지 도달할 수 있어야 한다.
2. **강조색은 하나**: 브랜드 버건디(`cooa`)가 유일한 강조색. 시맨틱 색(ok/warn)은 상태 전달에만.
3. **새 팔레트 생성 금지**: 모든 색은 아래 토큰에서만. 인라인 hex는 데이터 주입(`b[:color]`, 아바타 색 등 DB/모델 유래 값)만 허용.
4. **3중 신호**: 상태는 아이콘 + 라벨 + 색을 함께 (색맹 대응, 기존 규약 유지).
5. **미니멀리즘 사다리**: ①필요한가 ②이미 있나(재사용) ③표준/네이티브 ④한 줄이면 한 줄 ⑤아니면 최소. 단 검증·보안·접근성은 삭제 금지.
6. **Specs beat vibes**: 감으로 조정하지 말고 이 문서의 수치·규칙으로. 한 번에 변수 하나만 바꿔 비교한다.

## 1. 색 토큰 (`@theme`, 전체 16종)

| 토큰 | 값 | 역할 | 규칙 |
|---|---|---|---|
| `cooa` | #8e0300 | 브랜드/강조 (버건디) | 주요 CTA·활성·포커스 링 |
| `cooa-dark` | #280100 | 그라데이션 끝·hover | |
| `ink` | #3d3d3d | 본문 텍스트 | |
| `muted` | #5f6368 | 보조·메타 텍스트 | white 6.05:1 (AA 통과) |
| `line` | #a3a3a3 | **보더 전용** | `text-line` 금지 (대비 2.52:1) |
| `line-soft` | #d9d9d9 | 연한 보더/배경 | |
| `tint` / `tint-2` / `tint-3` | #f5f5f5 / #e9e9e9 / #d3d3d3 | 배경 틴트 / 상단바 / 탭 | |
| `accent` | #ffeeee | 강조 연틴트 | 선택 행·hover 배경 |
| `warn` / `warn-strong` | #e6a700 / #d99a00 | 위험신호 / 대기·요청 pill 채움 | 밝은 배경 위 텍스트 AA 불가 — 라벨은 ink, 색은 아이콘/보더로 |
| `warn-soft` | #fff7e0 | 주의 연틴트 배경 (기존 인라인색 토큰화, ok-soft와 동형) | |
| `ok` / `ok-strong` / `ok-soft` | #84b733 / #5f8f2e / #eef6e3 | 적합 / 확인 버튼·상태 / 연틴트 배경 | ok-strong 텍스트는 large만 AA |
| 유틸 | `.bg-cooa-gradient` | 브랜드 그라데이션 | 버전 칩 + 홈 히어로 CTA 예외 |

**금지**: 토큰 외 인라인 hex/스타일 색 (2026-07-10 전폐 완료 — 데이터 주입·아바타 팔레트만 예외). 모델 색 맵(annotation·decidable)은 `var(--color-*)` 토큰 참조가 정본.

## 2. 타이포 스케일

Pretendard Variable. 현행 6단계 + 확장 3단(§9-B 확정 대기, 현재 arbitrary 11곳의 승격 목표값):

| 토큰 | px | 용도 |
|---|---|---|
| `text-caption` | 11 | 캡션·뱃지·태그 (최소 하한 — 11px 미만 금지) |
| `text-meta` | 12 | 메타·보조 라벨 |
| `text-body` | 13 | 본문 기본 |
| `text-note` | 14 | 강조 라벨·소제목 |
| `text-lead` | 15 | 리드 문장·계정 카드명 |
| `text-section` | 16 | 섹션 제목 |
| `text-title` | 18 | 페이지 부제·사용자명 |
| `text-display` | 20 | 큰 제목 |
| `text-brand` | 22 | 워드마크·히어로 |

**규칙**: `text-[Npx]` arbitrary 금지. 필요한 크기가 없으면 토큰을 추가하고 이 표를 갱신한다. 가중치는 위계와 함께: 제목 700(bold)·강조 600(semibold)·본문 400.

## 3. 레이아웃·스페이싱

- **페이지/패널 좌우 패딩**: `px-6`. 헤더줄·하단 액션바는 상하 대칭 `py-*`.
- **폼 페이지 컨테이너**: `mx-auto max-w-3xl p-6` (members·settings). 인증 카드: `max-w-md`.
- **radius 규칙** (혼용 정리 기준):
  - `rounded-full` = pill·아바타·원형 뱃지
  - `rounded-lg` = 버튼(ui_button 고정)·리스트 행·인라인 아이템
  - `rounded-xl` = 독립 표면 카드(로스터·패널·빈 상태 카드)
  - `rounded-2xl` = 모달·히어로 카드(홈 작업실 카드)
  - `rounded-md` = 버전 칩 등 소형 사각 요소. 그 외 값(arbitrary) 금지.
- **빈 상태 표준 2종** (§5 참고): 카드형 `py-12` / 텍스트형 `py-8`. 그 외 패딩 임의값 금지.
- **작업 3화면(버전·비교·스크리닝) 표준**: 캔버스 gutter `p-3`(px-6의 문서화된 예외 — 아트워크 몰입 영역), 우측 패널 폭 `lg:w-[380px]` 단일. 인박스 본문 `px-6 py-4`(헤더 좌측 기준선 정렬).

## 4. 컴포넌트 정본 (ui_helper.rb)

- **버튼 = `ui_button` / `ui_button_classes` 단일 진실원**. 변형 5종: `primary`(채움 버건디) `secondary`(아웃라인) `ghost`(무테 저강도) `danger`(warn 아웃라인) `ok`(확인/반영 — ok-soft 배경+ok-strong 보더+ink 라벨). 크기 `sm`/`md`. radius `rounded-lg` 고정, focus-visible 링 내장.
  - **raw 버튼 마크업 금지**. gradient 예외는 단 2곳: `version_chip` + 홈 빈 상태 히어로 "새 작업실 만들기".
- **아이콘 단독 버튼 = `icon_button`** (aria-label 필수 인자 내장, 정사각 히트영역·rounded-lg·focus 링).
- **아이콘 = `ui_icon`** (lucide 스타일 인라인 SVG 29종, currentColor, **기본 aria-hidden**). **이모지 아이콘 금지**. 새 아이콘은 ICON_PATHS에 추가.
- **pill/뱃지**: 판정 `decision_pill` · 피드백 상태 `annotation_status_pill` — ink 라벨 + 시맨틱 색 보더/아이콘의 3중 신호가 정본. 순번 뱃지 = `seq_badge`(아웃라인形: 白배경+ink 글자+색 보더, 크기 16/20/28만). 품목코드 = `product_code_chip`.
- **select = `ui_select_classes`** (appearance-none+caret 배경+focus ring — 인풋과 동형).
- **터치/스크롤 유틸**: `.touch-target`(coarse 포인터에서 히트영역 ≥44px) · `.scroll-fade-x`(가로 스크롤 우측 페이드 단서).
- **아바타 = `avatar`** (이름 첫 글자 + avatar_color, 이름 없으면 미렌더).
- **버전 칩 = `version_chip`** (그라데이션 사각 + V#).
- **브레드크럼 = `node_breadcrumb`** (가시 조상만 — 권한 누출 차단. 변경 금지).
- **모달 크롬 표준**: `<dialog>` + `m-auto w-full max-w-md rounded-2xl border border-line bg-white p-0 shadow-2xl backdrop:bg-ink/40` + header/body/footer (현 2곳 중복 — partial 추출 예정).

## 5. 상태 표면

- **빈 상태 = `shared/_empty_state` partial 단일 진실원** — variant 2종:
  - *:card* (주요 목록이 비었고 행동 유도 필요): 아이콘(32) + 제목 + 설명 + 선택 CTA, `py-12`.
  - *:text* (패널·보조 목록): `py-8 text-center text-meta text-muted` 한 줄.
  - 모든 목록 화면은 빈 상태를 반드시 가진다. 단, 성공 상태(스크리닝 all-clear "위반·주의 사항 없음")는 빈 상태가 아니라 3중 신호 성공 표면으로 유지.
- **로딩**: 제출 버튼 = `submit_loading`(스피너+라벨 교체). 스피너 = `.spinner`(1em, currentColor, reduced-motion 대응). 드로어 = 클릭 즉시 슬라이드-인 + turbo-frame `[busy]` CSS 스피너.
- **에러**: `docs/error-handling.md` 규약 준수 — 대형 폼 인라인 422 재렌더, 소형 폼 flash alert, 전역 토스트 `net_error_toast`.
- **flash**: 우상단 토스트, notice 4s/alert 8s 자동소멸, `role=status`/`role=alert`.

## 6. 내비게이션

- 전역: 톱바(로고=홈·사이드바 토글·히스토리 탭) + 사이드바(인박스·구성원·컨텍스트 트리/작업실 목록).
- **풀페이지 작업 화면(버전/비교/스크리닝)은 브레드크럼 필수**. 드로어는 경로 라벨(`node_path_label`).
- 히스토리 탭은 풀페이지 작업만 (버전 v · 비교 c · 스크리닝 s).
- **모바일(lg 미만)**: 사이드바 오프캔버스(translateX+백드롭+Escape/resize 동기화+aria-expanded) — 톱바 토글로 접근 보장. 데스크톱 접힘(쿠키 영속)과 분리 동작.
- **드로어(제품 상세)**: `role=dialog aria-modal` + 열림 시 닫기 버튼 포커스 + Tab 트랩 + 닫힘 시 트리거 포커스 복원.

## 7. 접근성 (유지·강화 규칙)

- 전역 `:focus-visible` 링(버건디 2px). 인풋은 `focus:ring-1 ring-cooa` 자체 처리. **포커스 링 제거 금지**.
- **아이콘 단독 버튼은 `aria-label` 필수** (`title`만으로 불충분).
- 시맨틱 우선: `<dialog>`·`<details>`·`nav`·`aside`·`dl`. ARIA 롤은 기존 패턴(tablist/menu/combobox) 유지.
- 모션: 150~300ms, `prefers-reduced-motion` 대응 필수 (CSS+컨트롤러 이중).
- 대비: 본문 AA(4.5:1) — muted까지만 텍스트 허용, line은 보더 전용.

## 8. 안티패턴 (AI-slop 체크리스트)

- 이모지 아이콘 · 토큰 외 인라인 색 · `text-[Npx]` arbitrary · raw 버튼 마크업 · 무지개 강조색(기능마다 다른 색) · 포커스 링 제거 · 0ms 상태 전환 · 근거 없는 그라데이션/광택 · 같은 역할 다른 스타일(스크리닝 3중 표현이 대표 사례)

## 9. 결정 기록

- **A. 스크리닝(인허가 AI) 색 정책** (2026-07-09 확정): **브랜드 버건디로 수렴.** AI 기능 구분은 spark 아이콘+라벨로 전달한다. 보라(#6b4ea8)·핑크-보라 그라데이션은 제거. 강조색 1개 원칙(§0-2) 유지.
- **B. 타이포 확장 3단** (2026-07-09 확정): lead 15 / title 18 / brand 22 토큰 승격. `text-[Npx]` arbitrary 금지 발효(§2).
