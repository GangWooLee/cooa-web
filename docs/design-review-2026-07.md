# COOA web 디자인 리뷰 백로그 (2026-07-09)

> 기준 문서: `DESIGN.md`. 방법론: 스크린샷 기준선(11화면 × 3뷰포트 × 역할 3종, 45장) 위에서
> 10차원 파인더 + 차원별 adversarial 검증(2단, 전원 vision 사용). 55건 발견 → **53건 통과**(확정 43·조정 10·기각 2).
> 여기에 사전 실측 결함 6건(M1~M6)을 합쳐 우선순위 백로그로 정리. 상세 근거·수정 방향은 부록 A.

## 우선순위 요약

| 등급 | 기준 | 건수 |
|---|---|---|
| **P0** | 사용 차단 | M1 (모바일 사이드바) |
| **P1** | 기본기 위반 (접근성·대비·위계·일관성) | 16건 + M2·M3·M4 |
| **P2** | polish | 37건 + M5·M6 잔여 |

사전 실측(M): **M1** lg 미만 사이드바 소실(`_sidebar.html.erb:5`) · **M2** 스크리닝 색 3중 표현 ·
**M3** 타이포 arbitrary 11곳 · **M4** 피드백 패널 ~80줄 중복 · **M5** 빈 상태 표준 부재 · **M6** CTA raw 마크업.

## 실행 묶음 (Phase 3 — 파운데이션)

### WP1. 모바일 최소 접근 [P0]
- **M1**: lg 미만 오프캔버스 사이드바 + 톱바 햄버거 (`shared/_sidebar.html.erb:5`, `_topbar.html.erb`, `sidebar_controller.js`, CSS)
- **responsive-3 [P1]**: 모바일 스크리닝 하단 액션바가 콘텐츠 가림 (`screenings/screening.html.erb:111`)
- responsive-2: 모바일/태블릿 트리 테이블 잘림 — 가로 스크롤 페이드 단서 (풀 카드화는 Phase 4)

### WP2. 접근성 P1 일괄
- **forms-1/a11y-4**: 폼 label↔input `for/id` 연결 전수 (`members/index.html.erb:14`, `component_versions/_form.html.erb:20` 외)
- **forms-4**: 아바타 색 라디오 aria-label + fieldset/legend (`settings/show.html.erb:30`)
- **a11y-1**: 아이콘 단독 버튼 aria-label 전수 (`_topbar.html.erb:30` 외 — title만 있는 곳)
- **forms-2**: 인라인 편집 키보드 접근 + 상시 어포던스 (`products/_inline_meta.html.erb:5`)
- **states-3**: 스크리닝 finding 카드 div→button (`screenings/screening.html.erb:66`)
- **ia-nav-1**: 사이드바 활성 상태 hover와 분리(bg-accent+text-cooa) + aria-current (`_sidebar.html.erb:37,56`)
- a11y-6: `ui_icon` 기본 aria-hidden · a11y-5: 폼 오류 role=alert · a11y-2: 줌 버튼 접근 이름

### WP3. 색·대비 정합 [결정 A 이후]
- **M2 [결정 A]**: 스크리닝 액션 색 단일화 (`products/_detail.html.erb:110-117` 보라 / `screening.html.erb:121` 그라데이션 / `show.html.erb:206` 버건디)
- **color-1**: warn 앰버 저대비 — pill 라벨 ink화 + 아이콘/보더로 색 전달 (`decidable.rb:7`)
- **color-2**: '반영'·'active' 그린 저대비 — 라벨 ink화, 그린은 아이콘+배경으로 (`members/index.html.erb:75`, `annotation_status_pill`)
- **states-2**: 스크리닝 disabled 인라인 style이 disabled: 유틸 무력화 (`products/_detail.html.erb:116`)
- color-3: 모델 색 맵 토큰화(accent/tint/ok-soft) + 팔레트 밖 파랑 #4f74e3 수렴 (`annotation.rb:13`)
- a11y-7: `text-ink/60·70` → `text-muted` (`screening.html.erb:87`)
- 매직 그레이 정리 (`screening.html.erb:50-52`, `sessions/new.html.erb:42`)

### WP4. 타이포 스케일 [결정 B 이후]
- **M3 [결정 B]**: 토큰 3단 신설(15/18/22) + `text-[Npx]` 11곳 치환 (`application.css` + 뷰 7파일)
- **typography-1**: 인박스 헤딩 위계 승격 — H1 display/섹션 section (`reviews/index.html.erb:4`)
- **typography-2**: 버전 라벨 V5/v5 표기 단일화 — `vlabel` 정본 + `.upcase` 20곳 제거 (`component_version.rb:34`)
- typography-4: 워드마크 통일(auth 4화면 텍스트 'COOA' vs 로고 마크) · typography-5: 검색 placeholder 잘림

### WP5. 컴포넌트 정본화
- **M4**: 피드백 패널 partial 추출 (`component_versions/show.html.erb:95-186` ≒ `comparisons/show.html.erb:49-134`)
- **consistency-1 [P1]**: gradient 남용 회수 — 문서화된 2예외(버전 칩·홈 히어로)만 남김 (`dashboard/_list.html.erb:20` 외)
- consistency-2: `product_code_chip` 헬퍼 (3종 표기 통일) · consistency-3: `icon_button` 헬퍼(aria-label 내장)
- consistency-5: `seq_badge` 헬퍼 (5+파일 반복) · consistency-6: `BTN_VARIANTS[:ok]` 신설 → 확인/반영 CTA 이관
- consistency-4: Google 버튼 partial 추출 · consistency-7: `minus` 아이콘 추가(전각 ＋／－ 대체)
- M6: 잔여 raw 버튼 → ui_button (`_detail.html.erb:107`, `_component.html.erb:66,106`, `_form.html.erb:35`)

### WP6. 상태 표면
- **states-1 [P1]**: 드로어 turbo frame 로딩 표시 — 즉시 슬라이드인 + `.spinner`/스켈레톤 (`detail_drawer_controller.js:11`)
- M5: 빈 상태 표준 partial 2종(카드형 py-12 / 텍스트형 py-8) + 비교 화면 빈 상태 신설 + 인박스 빈 상태 승격
- forms-3: 새 버전 폼 필수 표시+required · forms-7: 인라인 'None'→'—'

## 실행 묶음 (Phase 4 — 화면별)

### WP7. 반응형
- **responsive-1 [P1]**: 비교 2-pane lg 미만 세로 스택 (`_artwork_viewer.html.erb:75`) — layout-5와 동일 건
- responsive-4: 터치 타깃 44px(줌·핀·칩·탭닫기) · responsive-6: 가로 스크롤 페이드 단서 3곳 통일
- layout-2: 드로어 타임라인 현재 버전 scroll-into-view

### WP8. 내비게이션 polish
- ia-nav-2: 히스토리 탭 '스크리닝' 뱃지 클리핑 — 타입 신호 좌측 이동 (`_topbar.html.erb:27`)
- ia-nav-3: depth-5 브레드크럼에 버전(depth-4) 링크 추가 · ia-nav-4: '← 모든 작업실' 11px→14px 승격
- ia-nav-5: 검색 스코프 라벨 명시('현재 작업실 한정') — 전역 검색은 별도 제품 결정

### WP9. 폼·레이아웃·스페이싱 polish
- forms-5: select 정본(appearance-none+캐럿) · forms-6: 역할 선택 role_picker로 수렴
- layout-1: 설정 정렬축 단일화 · layout-3: 드로어 dl 라벨 컬럼 · layout-4: 폼 페이지 폭 규약 통일
- spacing-1: 우패널 폭 360/380/400 통일 · spacing-2~5: 본문 px-6 정렬·카드 p-4·보안 행 py·탭 헤더 p-3
- a11y-3: 드로어 dialog 시맨틱+포커스 트랩 · a11y-8: reduced-motion 슬라이드 커버 · a11y-9: 발견 박스 3중 신호

## 미결정 (구현 착수 전 사용자 확인)

- **A. 스크리닝 색 정책**: 보라 토큰 승격(AI 시그니처) vs 버건디 수렴(단색 체계). → `DESIGN.md §9-A`
- **B. 타이포 확장 3단**: lead 15 / title 18 / brand 22 승격안. → `DESIGN.md §9-B`

## 기각된 findings (검증 탈락, 참고)

- typography-3: arbitrary 11곳 목록 자체는 타 finding과 중복 집계 — M3로 흡수
- responsive-5: `md:` 0회 주장 — 실사용상 sm/lg로 충분히 커버되는 지점이라 결함 아님

## 부록 A — 검증 통과 findings 전체 (53건)

| 심각도 | ID | 판정 | 화면 | 위치 | 요약 | 수정 방향 |
|---|---|---|---|---|---|---|
| P1 | a11y-1 | CONFIRMED | workspace | app/views/shared/_topbar.html.erb:30 | 아이콘 단독 액션 버튼(삭제·닫기·버전추가·새 폴더·탭 닫기)이 title만 있고 aria-label이 없어 DESIGN §7을 위반한다. | 각 button_to/link_to에 한글 aria-label 추가(예: aria-label: '탭 닫기'·'새 폴더'·'제품 삭제'). 이미 존재하는 title과 동일 문구를 aria-label로 병기하면 됨(신규 토큰 불필요). |
| P1 | a11y-4 | CONFIRMED | version-form | app/views/component_versions/_form.html.erb:20 | 폼 필드 라벨이 입력과 프로그램적으로 연결돼 있지 않다(for/id 없는 block <label>) — 다수 폼에 걸친 시스템 문제. | f.label :artwork(모델 폼) 사용하거나 raw 입력엔 id 부여 후 label에 for= 연결. 시각 변화 없이 연결만 추가. |
| P1 | color-1 | CONFIRMED | screening | app/models/concerns/decidable.rb:7 | 스크리닝 '주의'(warning) 판정색 #e6a700(warn)이 너무 밝아, 옅은-틴트 위 pill 텍스트로도(≈2:1) 흰 글자를 얹은 채움으로도(≈2:1) 모두 WCAG AA에 크게 미달한다. | 앰버 요소에서 저대비를 제거: (a) pill·요약칩 라벨은 ink(#3d3d3d, 어느 밝은 틴트에서도 AA)로 쓰고 색은 아이콘+좌측 4px 보더로만 전달(3중 신호 유지) (b) 흰 숫자를 얹는 seq 원형/카운트 사각은 앰버 채움에 어두운 ink 텍스트로 전환(앰버+흰색은 warn-strong으로도 AA 불가). pill 배경은 #fff7e0 대신 tint 토큰 계열로 정렬. |
| P1 | color-2 | CONFIRMED | members | app/views/members/index.html.erb:75 | '반영/active' 계열 그린이 렌더 크기에서 WCAG AA 미달 — annotation_status_pill '반영'은 #5f8f2e on #eef6e3 ≈3.46:1(11px), members 'active' 뱃지는 흰 글자 on ok-strong ≈3.85:1(11px). DESIGN.md 스스로 'ok-strong 텍스트는 large만 AA'라 명시했는데 caption/body로 쓰인다. | 그린 토큰은 이 팔레트에서 밝은 배경 4.5:1을 못 넘으므로(문서화된 한계), small 상태 요소에서 색을 '유일 신호'로 쓰지 말 것: '반영'·'active' 라벨은 ink로 렌더하고 그린은 check 아이콘 + ok-soft 배경으로 전달(3중 신호 유지). 흰 글자를 꼭 ok-strong에 얹어야 하면 large(≥14px bold) 로만 한정하거나 아이콘 병기로 보완. |
| P1 | consistency-1 | CONFIRMED | workspace | app/views/dashboard/_list.html.erb:20 | bg-cooa-gradient가 문서화된 2개 예외(버전 칩·홈 히어로 CTA)를 넘어 툴바 버튼·카드 아이콘 타일·품목코드 칩까지 번져 강조 위계가 흐려짐 | ‘새 폴더’는 ui_button primary(solid bg-cooa)·‘새 파일’은 secondary로 통일. 카드 아이콘 타일과 품목코드 칩은 solid bg-cooa 또는 bg-accent/text-cooa로 강등. gradient는 version_chip과 홈 히어로 CTA 2곳에만 남긴다. |
| P1 | forms-1 | CONFIRMED | settings | app/views/members/index.html.erb:14 | 폼 라벨이 입력과 프로그램적으로 연결되지 않음(for/id 부재) — 스크린리더가 필드 이름을 못 읽고 라벨 클릭도 포커스 이동 없음 | raw `<input>`/`<select>`를 `f.label`+`f.text_field`/`f.select`(자동 id·for) 또는 명시 `id`+`<label for>`로 교체. 기존 focus:ring-cooa 토큰·클래스 유지, 새 스타일 불필요. |
| P1 | forms-2 | CONFIRMED | product-drawer | app/views/products/_inline_meta.html.erb:5 | 인라인 편집 메타 필드가 키보드로 접근 불가하고, 편집 가능하다는 상시 시각 단서가 없음(hover에서만 드러남) | display를 `<button type="button">`(또는 tabindex=0+role+keydown Enter/Space)로 승격해 키보드 진입 확보. 동시에 연필 `ui_icon`이나 밑줄 등 상시 affordance 추가(기존 hover:text-cooa 토큰 재사용). |
| P1 | forms-4 | CONFIRMED | settings | app/views/settings/show.html.erb:30 | 아바타 색 라디오가 접근가능 이름이 없음(title=hex뿐, aria-label·fieldset/legend 부재) — 스크린리더가 색 옵션을 식별 못함 | 각 라디오에 사람이 읽을 수 있는 aria-label(예: '버건디'·'앰버' 등 색 이름, 없으면 '아바타 색 1'…)을 부여하고, 묶음을 `<fieldset>`+`<legend>아바타 색</legend>`로 감싼다. 팔레트/스타일 변경 없음. |
| P1 | ia-nav-1 | CONFIRMED | global | app/views/shared/_sidebar.html.erb:37 | 사이드바 '현재 위치' 활성 상태가 자기 hover 상태와 같은 색(bg-tint)이라 구분 불가 + aria-current 전무 | 활성 링크를 트리 현재 노드와 통일: bg-accent + text-cooa + font-semibold(호버=bg-tint와 명확히 분리) 로 두고 aria-current='page' 추가. 톱바가 이미 쓰는 aria-current 규약을 사이드바(인박스·구성원·트리 리프)에 일관 적용. |
| P1 | responsive-1 | CONFIRMED | comparison | app/views/shared/_artwork_viewer.html.erb:75 | 버전 비교의 좌우 2-pane가 어떤 뷰포트에서도 나란히(가로)만 배치돼, 모바일(각 ~180px)·태블릿(각 ~350px)에서 두 아트워크가 모두 판독 불가. | lg 미만에서 pane 컨테이너 방향을 세로 스택으로 전환하거나(flex-col), v5/v6 단일 표시 토글 제공. 색·팔레트 무변경, 레이아웃 유틸(flex-col/lg:flex-row)만. |
| P1 | responsive-3 | CONFIRMED | screening | app/views/screenings/screening.html.erb:111 | 모바일/태블릿에서 하단 액션바가 세로로 쌓인 결과·피드백 리스트와 충돌해 마지막 카드를 가린다 — 뷰어 min-height:380px + shrink-0 aside가 높이 고정 컨테이너를 넘쳐, 비-sticky 액션바가 콘텐츠 위로 겹침. | lg 미만에서 뷰어 min-height를 완화(sm+에서만 380px)하고 페이지 전체 스크롤 허용 + 액션바를 sticky bottom으로 두되 스크롤 컨테이너에 하단 패딩(pb) 확보. 레이아웃만, 색 무변경. |
| P1 | states-1 | CONFIRMED | product-drawer | app/javascript/controllers/detail_drawer_controller.js:11 | 제품 드로어 turbo-frame 페치 중 로딩 피드백이 전무해, 느린 네트워크에서 트리 행/사이드바 클릭 후 드로어가 뜰 때까지 아무 반응이 없다. | 클릭 즉시(트리 row_link/사이드바) 패널을 슬라이드-인하고 빈 #detail 프레임에 기존 .spinner(1em·currentColor·reduced-motion 대응) 또는 tint/line-soft 스켈레톤을 표시. 프레임의 [aria-busy] 속성으로 CSS만으로도 구동 가능 — 콘텐츠 도착 시 자연 교체. |
| P1 | states-2 | CONFIRMED | product-drawer | app/views/products/_detail.html.erb:116 | 드로어 액션바의 '스크리닝' 버튼은 disabled여도 인라인 style이 disabled:bg-line-soft를 이겨 보라색을 유지 → 옆의 '비교 열기'(회색으로 정상 비활성)와 disabled 상태가 서로 달라 보인다. | 스크리닝 버튼 배경을 인라인 style이 아니라 클래스/토큰(§9-A 확정 시 bg-cooa로 수렴)으로 배선해 disabled: 유틸이 이기게 하거나, 미확정 구간엔 disabled:grayscale를 추가해 두 버튼의 비활성 표현을 동일하게. 비활성 텍스트도 line-soft 위 white라 판독難 → disabled:text-muted 병행. |
| P1 | states-3 | CONFIRMED | screening | app/views/screenings/screening.html.erb:66 | 스크리닝 결과의 finding 카드는 click 액션이 달린 <div>여서 키보드로 포커스·실행이 불가하고 포커스 상태 표시도 없다(비교·버전 화면은 동일 목적에 <button> 사용). | 박스 지정(seq 존재) finding 카드를 <button type="button">로 렌더(비-박스 카드는 순수 div 유지) → 전역 focus-visible 버건디 링·키보드 실행이 자동 확보되고 비교/버전 화면과 상태 표현 일치. hover:border-cooa는 그대로. |
| P1 | typography-1 | CONFIRMED | inbox | app/views/reviews/index.html.erb:4 | 인박스 페이지 타이틀·섹션 헤딩이 동급 페이지보다 한 단계 작아 위계가 붕괴·역전된다 | reviews/index H1을 text-display(20px)로, '리뷰어 미배정' h2를 text-section(16px)로 승격해 동급 페이지 타이틀·섹션 헤딩 스케일과 정렬. 기존 토큰만 사용(새 값 없음). |
| P1 | typography-2 | CONFIRMED | comparison | app/views/comparisons/show.html.erb:52 | 동일 버전 식별자가 곳에 따라 'V5'(대문자)와 'v5'(소문자)로 갈려 렌더된다 | 대문자로 표준화: component_version.rb:34 vlabel을 "V#{version_number}"로 올리고 산재한 .upcase 호출(20+곳)을 제거하면 단일 진실원으로 전 화면 일치(미니멀리즘 사다리상 최적). 반대 방향(소문자 10곳에 .upcase 추가)도 가능하나 중복 잔존. |
| P2 | a11y-2 | CONFIRMED | version | app/views/shared/_artwork_viewer.html.erb:28 | 아트워크 뷰어 확대/축소 버튼이 전각 글리프 ＋/－ 텍스트만 있고 접근 이름(확대/축소)이 없다. | ＋ 버튼 aria-label='확대', － 버튼 aria-label='축소' 추가. 글리프 대신 ui_icon plus/minus로 교체하면 시각 일관성도 함께 개선(그래도 aria-label 유지). |
| P2 | a11y-3 | ADJUSTED | product-drawer | app/javascript/controllers/detail_drawer_controller.js:24 | 제품 상세 드로어가 모달 시맨틱과 포커스 관리가 없다 — role=dialog/aria-modal 부재, 열 때 포커스 이동 없음, 포커스 트랩·복원 없음. | 패널에 role='dialog' aria-modal='true' aria-labelledby(제품명 h1 id) 부여, open() 시 닫기 버튼 또는 제목으로 focus() 이동, 열린 동안 배경에 inert(또는 aria-hidden), Tab 순환 트랩, close() 시 이전 트리거로 포커스 복원. 순수 접근성 배선이라 토큰 변경 없음. |
| P2 | a11y-5 | ADJUSTED | version-form | app/views/component_versions/_form.html.erb:10 | 버전 폼의 유효성 오류 요약이 role=alert/aria-live 없이 렌더돼 422 재렌더 시 SR에 오류가 알려지지 않는다. | 오류 요약 컨테이너에 role='alert'(또는 aria-live='assertive') 부여, 실패 필드엔 aria-invalid='true'와 aria-describedby로 메시지 연결. |
| P2 | a11y-6 | CONFIRMED | workspace | app/helpers/ui_helper.rb:40 | ui_icon 헬퍼가 장식용 SVG에 aria-hidden을 붙이지 않아 전 앱 아이콘이 접근성 트리에 이름 없이 노출된다. | ui_icon 기본 출력에 aria-hidden='true'(또는 focusable='false') 추가. 의미를 단독으로 전달하는 극소수 아이콘만 opt-out 인자로 aria-label 부여. |
| P2 | a11y-7 | CONFIRMED | screening | app/views/screenings/screening.html.erb:87 | 틴트 배경 위 불투명도 희석 텍스트(text-ink/60·text-ink/70)가 대비 AA 4.5:1을 못 넘긴다. | text-ink/60·text-ink/70 보조 텍스트를 text-muted 토큰으로 교체(AA 통과). 이후 유사 희석 패턴(component/show·comparison show의 text-ink/80은 통과이므로 유지 가능) 전수 확인. |
| P2 | a11y-8 | CONFIRMED | workspace | app/assets/tailwind/application.css:111 | prefers-reduced-motion이 사이드바 슬라이드·드로어 슬라이드 등 사용자 트리거 트랜지션을 커버하지 않는다. | @media (prefers-reduced-motion: reduce) 블록에 #app-sidebar { transition:none } 과 드로어 패널 transition:none(또는 유틸 대체) 추가. 토큰 무관. |
| P2 | a11y-9 | CONFIRMED | screening | app/views/shared/_artwork_viewer.html.erb:86 | 스크리닝 발견 박스가 아트워크 오버레이에서 판정을 색으로만 구분하고(위반=빨강/주의=앰버) 라벨·아이콘 없이 순번만 표시한다. | 박스 배지에 판정 아이콘(decision_meta[:icon]) 병기 또는 박스 <button>에 aria-label='위반: {subject}'식 접근 이름 부여(색+아이콘/라벨 3중 신호 복원). 색은 기존 판정 토큰 유지. |
| P2 | color-3 | ADJUSTED | workspace | app/models/annotation.rb:13 | 모델 색 맵(annotation·decidable)이 토큰 시스템을 우회해 팔레트 밖 색을 도입한다 — 특히 annotation 카테고리 '디자인'=#4f74e3(파랑, COOA 팔레트에 없는 완전 이색)과 '기타'=#6b7280(비토큰 회색), 그리고 accent/tint/ok-soft를 근사한 비토큰 hex 중복. | 색 맵을 CSS 토큰(var())로 이관: 배경 #fdeceb→accent, #f1f1f1→tint, #eef6e3→ok-soft로 치환하고 #fff7e0는 warn-soft 토큰을 신설해 대체. 팔레트 밖 파랑(#4f74e3, '디자인')은 제거하고 기존 토큰(예: 회색 line/muted 또는 ink)으로 수렴하거나, 카테고리 구분이 정말 필요하면 아이콘/라벨로 구분하고 색은 브랜드 한 축 안에서 명도만 달리한다(무지개 회피). |
| P2 | consistency-2 | CONFIRMED | product-drawer | app/views/products/_detail.html.erb:19 | 동일 데이터(품목코드 [CO000x])가 화면마다 3가지 마크업으로 표기 — gradient 흰 칩 / 회색 tint 칩 / 대괄호 평문 — 식별자 정본이 없음 | `product_code_chip(code)` 헬퍼 하나로 통일(예: rounded bg-tint px-1.5 py-0.5 text-caption font-bold text-ink/70). gradient 버전은 §1 위반이므로 제거하고, 톱바 탭도 같은 칩 또는 최소한 동일 tint 배경으로 맞춘다. |
| P2 | consistency-3 | CONFIRMED | product-drawer | app/views/products/_detail.html.erb:14 | 아이콘 단독 버튼(닫기 X·삭제·토글)이 곳곳에서 손수 작성돼 radius·padding·색·아이콘 크기가 제각각 — 공용 아이콘 버튼 컴포넌트 부재 | ui_helper에 `icon_button(name, size:, label:, variant:)` 추가(정사각 타깃·rounded-lg·focus 링·aria-label 필수 내장) 후 닫기/삭제/토글을 모두 이관. 닫기 X 아이콘 크기는 16으로 단일화. |
| P2 | consistency-4 | CONFIRMED | login | app/views/sessions/new.html.erb:17 | Google 로그인 버튼(인라인 4-path SVG + 흰 원형 칩 + button_to)이 두 파일에 글자까지 동일하게 복제 — 앱 내 유일한 ui_icon 우회 인라인 SVG | `shared/_google_button.html.erb`(label 로컬)로 추출해 두 화면에서 render. SVG는 그 partial 안에 1회만 둔다. |
| P2 | consistency-5 | CONFIRMED | version | app/views/shared/_artwork_viewer.html.erb:50 | 순번 배지(피드백·finding 번호 원)가 5+개 파일에서 손수 반복돼 크기(h-4/h-5/h-7)와 채움/아웃라인 방식이 제각각 — 컴포넌트 부재 | `seq_badge(label, color:, size:, style: :fill·:outline)` 헬퍼로 통일하고 크기 토큰은 2~3종(sm 16 / md 20 / nav 28)만 허용한다. |
| P2 | consistency-6 | CONFIRMED | version | app/helpers/ui_helper.rb:133 | ‘커밋’ 성격 CTA가 ui_button primary·raw bg-ok-strong·raw pink gradient로 흩어짐 — BTN_VARIANTS에 ok 변형이 없어 확인 계열을 정본화조차 못 함 | BTN_VARIANTS에 `ok: "bg-ok-strong text-white hover:bg-ok"`를 추가해 반영/확인 계열을 ui_button(variant: :ok)으로 이관한다. (스크리닝 실행 버튼 색은 DESIGN.md §9-A 색 정책 결정에 종속.) |
| P2 | consistency-7 | CONFIRMED | version | app/views/shared/_artwork_viewer.html.erb:28 | 아트워크 줌 컨트롤이 ui_icon 대신 전각 글자 ＋／－를 아이콘으로 사용 — ICON_PATHS에 minus가 없어 아이콘 체계 우회 | ICON_PATHS에 "minus"('<path d="M5 12h14"/>')를 추가한 뒤 zoomIn=ui_icon "plus", zoomOut=ui_icon "minus"로 교체한다. ‘전체’ 라벨은 텍스트 유지 가능. |
| P2 | forms-3 | ADJUSTED | version-form | app/views/component_versions/_form.html.erb:20 | 새 버전 폼에서 필수인 아트워크 파일이 필수 표시도 client `required`도 없어, 빈 제출 시 서버 422 왕복으로만 알게 됨 | 공유 폼이므로 `!persisted`(신규)일 때만 라벨에 필수 마크(예: cooa 색 별표 또는 '필수' text-caption)와 `required: true`를 붙인다. edit(파일 유지 가능)에는 미적용. |
| P2 | forms-5 | CONFIRMED | settings | app/views/settings/show.html.erb:40 | 네이티브 select가 appearance-none·커스텀 캐럿 없이 OS 기본 드롭다운으로 렌더 — 버건디 포커스 텍스트 인풋과 시각 무게·포커스/패딩이 불일치 | ui_helper에 select 정본(appearance-none + `ui_icon "caret"` 배경 + border-line-soft·rounded-lg·focus:border-cooa focus:ring-1 ring-cooa)을 신설해 전 화면 통일. 새 색 없이 기존 토큰만 사용. |
| P2 | forms-6 | CONFIRMED | members | app/views/members/index.html.erb:20 | 역할 선택 UI가 두 갈래 — 라디오-카드 피커(설명 노출)와 밋밋한 네이티브 select(설명 소실)가 같은 결정에 혼용됨 | 역할 선택을 _role_picker 라디오-카드로 수렴(공간 제약 폼은 최소한 select option에 역할 설명을 병기하거나 옆에 role_description 힌트 노출). 기존 partial 재사용이라 신규 스타일 불필요. |
| P2 | forms-7 | CONFIRMED | product-drawer | app/views/products/_inline_meta.html.erb:6 | 인라인 메타 빈값이 한국어 UI에서 영문 'None'으로 표시됨 | 'None' → '없음' 또는 중립 '—'(muted)로 교체. 텍스트 문자열만 변경. |
| P2 | ia-nav-2 | ADJUSTED | screening | app/views/shared/_topbar.html.erb:27 | 히스토리 탭의 '스크리닝' 뱃지가 tab-fade 마스크에 잘려 스크리닝 탭과 버전 탭이 사실상 동일하게 보임 | 타입 신호를 마스크에 먹히지 않는 위치로 이동: '스크리닝' 뱃지(또는 accent 좌측 마커)를 [코드] 바로 뒤·오버플로되는 '컴포넌트+vlabel' 라벨 앞에 배치하거나, 좌측 아이콘을 text-cooa로 승격해 타입을 좌단에서 즉시 읽히게. 새 색 없이 accent/cooa 토큰만 사용. |
| P2 | ia-nav-3 | CONFIRMED | screening | app/views/screenings/screening.html.erb:11 | depth-5(스크리닝/비교) 브레드크럼이 depth-4(버전)로 올라가는 링크를 제공하지 않음 | trailing을 분해: '단상자 V5'는 component_version_path 링크(text-muted hover:text-cooa)로, '인허가 스크리닝'/'버전 비교'만 현재 페이지 text-ink로. node_breadcrumb에 linked penultimate 인자를 추가하거나 뷰에서 버전 링크를 명시 전달. |
| P2 | ia-nav-4 | CONFIRMED | workspace | app/views/shared/_sidebar.html.erb:67 | '← 모든 작업실' 복귀 링크가 11px·muted로, 사이드바에서 가장 작은 상호작용 텍스트(위계 역전) | text-note(14px)로 승격해 트리 항목과 위계 정렬, hover:text-cooa 유지(또는 text-ink). 필요 시 ui_icon로 화살표 대체해 아이콘+라벨 구성. 토큰 내(note/muted/cooa)에서 해결. |
| P2 | ia-nav-5 | ADJUSTED | global | app/views/shared/_sidebar.html.erb:76 | 검색 발견성 결여: 작업실 밖에선 검색 어포던스 자체가 없고, 안에서도 현재 작업실 트리만 거르는 클라이언트 필터 | 제품 결정 필요(스코프 이슈). 최소한 검색이 '현재 작업실 트리 한정'임을 플레이스홀더/보조라벨로 명시해 오해 방지. 교차 작업실 발견이 필요하면 톱바 상시 검색 엔트리 검토(별도 제품 결정) — 신규 팔레트 없이 기존 search 아이콘·muted 토큰으로. |
| P2 | layout-1 | CONFIRMED | settings | app/views/settings/show.html.erb:10 | 설정 프로필 카드에서 '이름' 필드만 아바타 오른쪽으로 들여쓰기되어, 아래 '아바타 색'·'직무' 라벨의 좌측 정렬축과 어긋난다. | 아바타를 라벨 정렬축 밖(카드 우측 프리뷰 등)으로 빼거나, 이름·아바타색·직무를 모두 같은 좌측 edge에 정렬해 단일 정렬축 유지. COOA 토큰 그대로, 구조만 조정. |
| P2 | layout-2 | CONFIRMED | product-drawer | app/views/products/_component.html.erb:33 | 제품 드로어의 구성요소 버전 타임라인이 모바일 폭에서 넘쳐, 가장 중요한 '현재 버전' 칩(버건디)과 '+새 버전'이 우측에서 잘린다. | 활성 칩을 초기 scroll-into-view로 노출(현재 버전 우선), 또는 우측 페이드/그림자로 스크롤 여지 시각화. 좁은 폭에서는 타임라인을 최신(우측) 기준으로 시작. |
| P2 | layout-3 | CONFIRMED | product-drawer | app/views/products/_detail.html.erb:56 | 드로어 메타 dl의 라벨 컬럼이 4.5rem 고정이라 '담당자 (표시용 · 권한과 무관)' 긴 라벨이 좁은 컬럼에서 어색하게 2줄로 접힌다. | 부가설명을 라벨 컬럼 밖(값 아래 캡션 또는 라벨 우측 별도 배치)으로 빼거나 라벨 컬럼을 auto/min-content로 두어 담당자 라벨이 한 줄로 들어오게. text-caption text-muted 토큰 유지. |
| P2 | layout-4 | ADJUSTED | version-form | app/views/component_versions/new.html.erb:2 | '새 버전 추가' 폼 컨테이너가 다른 폼 페이지(구성원·설정)와 달리 좁은 max-w-xl·px-5로 렌더되어 폼-페이지 폭/패딩 규약이 어긋난다. | 폼 페이지 컨테이너를 표준 `mx-auto w-full max-w-3xl p-6`(또는 최소 px-6)로 통일. 2필드 폼이라 더 좁게 유지하려면 그 폭 규약을 DESIGN §3에 명문화 후 일관 적용. |
| P2 | layout-5 | CONFIRMED | comparison | app/views/shared/_artwork_viewer.html.erb:75 | 듀얼 페인 아트워크 뷰어가 어떤 폭에서도 두 버전을 가로로만 배치해, 모바일에서 v5·v6 도안이 각 ~180px로 쪼그라들어 판독 불가에 가깝다. | 좁은 폭(예: lg 미만)에서 panes를 세로 스택(`flex-col`)으로 전환해 각 버전을 전체 폭으로 렌더, 또는 버전 토글/스와이프 단일뷰 제공. 데스크톱 side-by-side는 유지. |
| P2 | responsive-2 | ADJUSTED | workspace | app/views/dashboard/_list.html.erb:44 | 모바일에서 작업실 트리 테이블이 7개 컬럼 중 3개만 보이고 담당자·구성요소·기한이 전부 화면 밖 — 카드형 대체 레이아웃 없이 860px 고정 테이블을 가로 스크롤로만 접근(스크롤 단서도 슬림 스크롤바뿐). | sm/md 미만에서 테이블을 행-카드(제품명 + 코드·국가·기한 메타 스택)로 접거나 핵심 컬럼만 우선 노출. 최소한 가로 스크롤 어포던스(우측 페이드 gradient) 추가. 기존 line-soft/tint 토큰 내. |
| P2 | responsive-4 | ADJUSTED | version | app/views/shared/_artwork_viewer.html.erb:28 | 아트워크 뷰어의 주요 인터랙션 요소가 44px 터치 최소치를 크게 밑돎 — 줌 ＋/－/전체 h-7 w-8(28×32), 영역 표시 h-7(28), 피드백 핀 h-7 w-7(28), 버전 칩 28-30px, 탭 닫기 x ~22px. 마우스 기준 크기 그대로 모바일에 노출(터치 확대 없음). | 터치/좁은 뷰포트에서 인터랙티브 컨트롤 히트영역을 ≥44px로(패딩 또는 min-h/min-w, 시각 크기는 유지한 채 클릭 영역 확장). 아이콘 단독 버튼 aria-label은 유지(§7). |
| P2 | responsive-6 | CONFIRMED | product-drawer | app/views/products/_component.html.erb:33 | 가로 스크롤 칩/핀 행이 모바일에서 항목을 잘라내면서 스크롤 단서가 없다 — 드로어 버전 타임라인(V5+ 화면 밖)·아트워크 피드백 핀 행(핀 5 클립)이 slim 스크롤바 뒤로 숨고, 버전 형제 스위처는 아예 오버플로 처리조차 없음(불일치). | 좁은 뷰포트에서 가로 스크롤 어포던스(우측 페이드 gradient 또는 스크롤 인디케이터) 추가, 세 곳(드로어 타임라인·피드백 핀·형제 스위처)의 오버플로 처리를 overflow-x-auto로 통일. 색 무변경, 유틸만. |
| P2 | spacing-1 | ADJUSTED | version·comparison·screening | app/views/screenings/screening.html.erb:35 | 우측 피드백·결과 패널 폭이 세 작업 화면에서 360/380/400px로 제각각(arbitrary 매직넘버) | 세 aside 폭을 단일 값(예: lg:w-[380px])으로 통일. 반복 매직넘버를 부분템플릿/상수 한 곳으로 뽑아 세 화면이 같은 폭을 공유하게 함(신규 팔레트 아님, 스페이싱만). |
| P2 | spacing-2 | CONFIRMED | inbox (+version·comparison·screening) | app/views/reviews/index.html.erb:7 | 본문 좌우 패딩이 헤더 px-6와 어긋남 — 인박스 본문 p-4, 작업 3화면 본문 p-3로 좌측 기준선 3종 | 인박스 본문 p-4→px-6로 헤더와 좌측 정렬. 작업화면 캔버스 p-3를 breathing gutter로 유지할 거면 그 예외를 DESIGN.md §3에 명문화(현재는 문서와 코드 불일치). |
| P2 | spacing-3 | CONFIRMED | settings·members | app/views/members/index.html.erb:10 | 설정형 두 페이지의 표면 카드 내부 패딩 불일치 — settings p-4 vs members p-3 | 표면 카드 내부 패딩을 p-4로 통일(members 초대 폼·scoped 안내 카드 p-3→p-4). |
| P2 | spacing-4 | CONFIRMED | settings | app/views/settings/show.html.erb:74 | 보안 카드 두 행의 수직 패딩 비대칭 — 첫 행 py-1(4px) vs 둘째 행 py-3(12px) | 두 행 모두 py-3(또는 py-2)로 통일해 행 리듬을 맞춤. 첫 행에도 상단 여백 부여. |
| P2 | spacing-5 | CONFIRMED | version | app/views/component_versions/show.html.erb:65 | version 우패널 탭 헤더 패딩 불일치 — 정보 탭 p-4 vs 피드백 탭 p-3 | 정보 탭 헤더 블록 p-4→p-3로 통일(피드백/상세/새폼과 동일). |
| P2 | typography-4 | CONFIRMED | login | app/views/sessions/new.html.erb:4 | 워드마크가 로그인 상태(소문자 그래픽 'cooa')와 진입 페이지(대문자 텍스트 'COOA')로 갈린다 | auth 헤더도 톱바와 동일 logo.png(소문자 마크)를 image_tag로 렌더해 워드마크 통일. 텍스트 유지가 불가피하면 로고 마크와 동일 형태로 맞춘다. |
| P2 | typography-5 | CONFIRMED | home | app/views/shared/_sidebar.html.erb:77 | 사이드바 검색 placeholder가 음절 중간에서 잘려 '…품목코드, 큳'처럼 깨져 보인다 | placeholder 카피 단축('아트워크 찾기' 또는 '품목코드·품목명 검색') + 유휴 시 pr-16→pr-8(count/clear가 나타날 때만 우측 여백 확보). text-[15px]는 typography-3 토큰 치환에 합류. |
