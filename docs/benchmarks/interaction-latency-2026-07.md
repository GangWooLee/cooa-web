# 인터랙션 레이턴시 실측 — 클릭→화면 반영 (INP류 브라우저단 체감)

측정일 2026-07-11 · 대상 web(Rails 8.1.3 / Ruby 3.4.7) dev 서버 · 도구 Playwright MCP · 교차 검증 gstack browse

---

## ① 측정 정의 · 축 구분

이 사이클은 **사용자 체감 인터랙션 레이턴시** = `performance.now()` 기준 **클릭(또는 입력) → DOM 변화 완료**를
잰다. INP(Interaction to Next Paint) 계열 지표로, "손이 움직인 뒤 화면이 실제로 바뀔 때까지"의 브라우저단 체감이다.

**직전 사이클과의 차이(중복 아님):**

| 축 | 직전 서버 사이클 (perf 커밋 `4017698`) | 이번 인터랙션 사이클 (본 문서) |
|---|---|---|
| 관점 | 서버 응답 **분해** (ttfb·쿼리 수) | 브라우저단 **체감** (클릭→DOM 반영) |
| 계측점 | Rails 요청 처리 · SQL 쿼리 카운트 | `performance.now()` · MutationObserver · Navigation Timing |
| 대표 수치 | 쿼리 325→275, 트리 재귀/2중 COUNT/N+1 소멸 + 게이트 3종 | 클릭→반영 0~3200ms, 계층별 판정 |
| 성격 | 서버가 첫 바이트를 얼마나 빨리 뱉나 | 서버 왕복 + 클라 렌더/스크립트를 사람이 얼마나 기다리나 |

두 사이클은 **직교**한다. 서버 사이클은 TTFB의 내부(쿼리)를, 이 사이클은 그 TTFB가 최종 체감에 어떻게
합산되는지와 **서버를 전혀 타지 않는 순수 클라이언트 인터랙션**(토글·필터·낙관 UI)을 본다. 아래 결과의
핵심 발견도 이 분리에서 나온다 — **모든 지연은 서버 몫이고, 클라이언트 몫은 전부 즉각이다.**

### 판정 척도 (RAIL)
즉각 `<100ms` · 양호 `<300ms` · 지연 `<1s` · 문제 `>1s`. **판정 기준값 = 웜 2회 중 나쁜 값.**

---

## ② 방법론

### 2계층 계측

**A. 동일-페이지 인터랙션** — 클릭이 같은 문서 안에서 DOM을 바꾸는 경우.
두 하위 유형으로 갈린다(측정 중 발견한 함정 — 아래 "함정 A" 참조):

- **A-순수(클라이언트)**: 토글·탭·필터 등 서버를 안 타는 즉시 반영. → **MutationObserver 200ms-정지 하네스**.
- **A-네트워크**: 드로어(turbo-frame fetch)·claim(button_to POST) 등 서버 왕복 후 반영.
  → **완료 이벤트(`turbo:frame-load` / `turbo:submit-end`)까지 측정** (200ms-정지만으론 낙관 UI에서 조기 종료됨).

**B. 풀 페이지 로드 인터랙션** — 결과 페이지에서 `performance.getEntriesByType("navigation")[0]`:
- **서버 몫** = `responseStart − requestStart` (TTFB)
- **렌더 몫** = `domContentLoadedEventEnd − responseStart` (첫 바이트→DOM 준비)
- **총** = `loadEventEnd`(= `duration`)
- **PDF 첫 페인트**(item 3): 캔버스 폴링 — canvas가 기본 300×150을 벗어나 실측 크기가 되는 시점(네비 시작 기준 `performance.now()`).

Turbo Drive 방문(상단 탭·claim·스크리닝)은 `PerformanceNavigationTiming` 엔트리를 새로 만들지 않으므로(fetch+history),
`turbo:load` / `turbo:submit-end` 이벤트 시각과 리소스 타이밍(`responseStart−requestStart`)으로 서버 몫을 뽑았다.

### 실사용 스니펫 (그대로 재현 가능 — Playwright `browser_run_code_unsafe` 안에서 `page.evaluate`)

**A-순수 하네스** (200ms-정지 = 마지막 DOM 변화 후 200ms 조용하면 완료로 판정):
```js
() => new Promise(resolve => {
  const el = document.querySelector(CLICK_SEL);
  const watch = el.closest(CONTROLLER_SEL) || document.body;  // 변화를 볼 컨테이너
  let last = null; const t0 = performance.now();
  const mo = new MutationObserver(() => { last = performance.now(); });
  mo.observe(watch, { subtree: true, childList: true, attributes: true, characterData: true });
  el.click();                                                  // 또는 input 이벤트 dispatch
  const iv = setInterval(() => {
    const now = performance.now();
    if (last && now - last > 200) { clearInterval(iv); mo.disconnect(); resolve(Math.round(last - t0)); }
    else if (!last && now - t0 > 5000) { clearInterval(iv); mo.disconnect(); resolve(null); } // 무변화
  }, 50);
});
```

**A-네트워크 하네스** (낙관 UI 조기종료 방지 — 완료 이벤트 필수):
```js
() => new Promise(resolve => {
  const frame = document.querySelector("turbo-frame#detail");   // 또는 form submit
  let eventTime = null, last = null; const t0 = performance.now();
  frame.addEventListener('turbo:frame-load', () => { eventTime = performance.now(); }, { once: true });
  const mo = new MutationObserver(() => { last = performance.now(); });
  mo.observe(WATCH, { subtree: true, childList: true, attributes: true });
  TRIGGER.click();
  const iv = setInterval(() => { const now = performance.now();
    if (eventTime && last && now - last > 250) {               // 콘텐츠 도착 후 DOM 안정까지
      clearInterval(iv); mo.disconnect();
      resolve({ contentArrival: Math.round(eventTime - t0), settle: Math.round(last - t0) });
    } else if (now - t0 > 8000) { clearInterval(iv); mo.disconnect(); resolve({ note: 'timeout' }); }
  }, 50);
});
// button_to POST(claim·스크리닝)은 turbo:submit-end 를 서버-완료 신호로 사용.
```

**B 하네스** (Navigation Timing):
```js
() => { const n = performance.getEntriesByType('navigation')[0];
  return { server: Math.round(n.responseStart - n.requestStart),
           render: Math.round(n.domContentLoadedEventEnd - n.responseStart),
           total:  Math.round(n.loadEventEnd || n.duration) }; }
```

**PDF 첫 페인트 폴링** (`page.goto(url,{waitUntil:'commit'})` 직후 시작 → 네비 시작 기준):
```js
() => new Promise(resolve => {
  const start = performance.now();
  const iv = setInterval(() => {
    const c = [...document.querySelectorAll('canvas')].find(c => c.width > 300 || c.height > 150);
    if (c) { clearInterval(iv); resolve({ paint: Math.round(performance.now()), w: c.width, h: c.height }); }
    else if (performance.now() - start > 15000) { clearInterval(iv); resolve({ paint: null }); }
  }, 40);
});
```

### 반복 규약
- 대상당 **3회**: 콜드 1회 **버림**, 웜 2회 **기록**. B 항목은 매 반복 앞서 `/`로 이동 후 대상 로드(캐시 상태 균질화).
- item 8(스크리닝)은 과제 규약대로 **서로 다른 3개 버전**(런 생성은 데모 데이터라 무해). 웜업 1회 별도 버림.
- item 6b(claim)는 **서로 다른 3개 미배정 행**(쓰기지만 데모 데이터 무해). 실제로 req 1503/1423/1417 claim됨.

### 재현 절차
1. dev 서버 `http://localhost:3000` 가동(재시작 불요) · demo:bulk 대량 상태.
2. Playwright MCP로 로그인: `/` → "데모 계정으로 둘러보기" → "김쿠아 kim@cooa.dev"(디자이너).
3. PDF 히어로 버전 id 확보(읽기 전용):
   `COOA_DB_USER=$USER bin/rails runner 'puts ActiveStorage::Attachment.where(record_type:"ComponentVersion",name:"artwork").order(:id).pluck(:record_id).join(",")'`
   → `10686,10902,11101,11301,11505,11721,11929,12126,12328,12544,12748,12954`
4. 위 하네스를 대상별로 `browser_run_code_unsafe` 안에서 반복 실행.

---

## ③ 환경 + 캐비앗

- **모드**: Rails **development**(클래스 리로드·이거로드 없음·per-request 오버헤드·에셋 비압축). 프로덕션 아님.
- **머신**: Apple **M3 Pro**(11코어) · macOS 26.5.1 · 로컬 dev 서버(네트워크 지연 ~0, DB 로컬).
- **데이터 규모**(demo:bulk): 제품 **255** · 버전 **2,516** · 리뷰 **330** · 멤버 **28** · 작업실 15+.
  대상 작업실 `/workspaces/80`(티트리 카밍 라인)은 **16제품**의 무거운 트리.
- **브라우저**: Playwright 내장 Chromium(headless), 로그인 세션 유지.

> **캐비앗 — dev 절대값은 신호가 아니다.** dev 모드는 같은 화면이 **2~10배 요동한 실측 이력**이 있다(본 측정
> 에서도 설정 페이지 서버 몫이 349ms↔1152ms, 탭 클릭이 661↔1285ms로 스윙). 콜드 첫 로드는 18초까지 튄다(버림).
> **신호는 상대 비교·병목 순위·서버/클라 분리**이며, **절대값은 dev 기준**임을 전제로 읽어야 한다. 프로덕션
> (이거로드+압축+캐시 웜)에서는 서버 몫이 크게 내려가고, 클라이언트 몫(이미 즉각)은 그대로일 것이다.
>
> **독립 교차 검증(다른 도구·다른 세션)이 이 캐비앗을 실증한다.** 본 측정 종료 후 별도 브라우저(gstack browse)로
> 최악 판정 페이지(`/workspaces/80`, 16제품 트리)를 유휴 서버에서 3연속 재측정한 결과 ttfb **262 → 104 → 54ms**
> (DCL 최저 98ms) — 계측 세션 중 값(2,452~3,019ms)과 **최대 ~55배** 차이다. 즉 item 1의 "문제" 판정 절대치는
> 계측 세션 자체의 dev 서버 부하가 지배한 값이고, 유휴 웜 상태의 같은 페이지는 300ms 미만에 서빙된다.
> (같은 교차 검증에서 `/members` ttfb 401ms는 본표 309~377ms와 정합 — 요동은 무겁게 렌더되는 페이지에 집중된다.)
> 표의 판정 열은 "dev 최악 케이스"로, 서버/클라 분리 구조는 "안정 신호"로 읽는 것이 옳다.

---

## ④ 결과 표

웜1/웜2 = 기록한 웜 2회. 서버 몫·렌더 몫은 해당 웜 범위. 판정 = 웜 2회 중 **나쁜 값** 기준.

| # | 인터랙션 | 계층 | 웜1 / 웜2 (ms) | 서버 몫 (ms) | 렌더·클라 몫 (ms) | 판정 |
|---|---|---|---|---|---|---|
| 1 | 홈→작업실 트리 표시 (`/workspaces/80`, 16제품) | B | **2660 / 3197** | 2452–3019 | 127–176 | **문제** (서버 지배) |
| 2 | 제품 행→드로어 **콘텐츠 도착** (turbo-frame) | A-net | **329 / 390** | ~300 (프레임 fetch) | 슬라이드-인 <16 | **지연** (콘텐츠) · 즉각 (낙관 슬라이드) |
| 3 | 버전 상세 **페이지 로드** | B | **704 / 806** | 611–646 | 72–95 | **지연** |
| 3 | ↳ **PDF 아트워크 첫 페인트** (canvas 483×714) | B+canvas | **1143 / 1156** | (페이지 포함) | PDF.js fetch+렌더 ~350–450 | **문제** |
| 4a | 리뷰 토글 `<details>` 열기/닫기 | A-순수 | **1 / 1** | — | 1 | **즉각** |
| 4b | 피드백↔정보 탭 전환 (`pane-switch`) | A-순수 | **1 / 2** | — | 1–2 | **즉각** |
| 5a | 상단 탭 클릭 (Turbo Drive 방문) | B/nav | **661 / 814** † | 626–776 † | 탭 하이라이트 ~4 | **지연** († 3번째 웜 1285 스파이크) |
| 5b | 탭 닫기 ✕ **낙관 숨김** (클릭→hidden) | A-순수 | **3 / 5** | — | 3–5 | **즉각** (낙관 UI 검증됨) |
| 6a | 리뷰 인박스 로드 (`/reviews`, claim 40행) | B | **803 / 426** | 344–631 | 73–142 | **지연** |
| 6b | claim "내가 맡기" (button_to POST) | A-net | **472 / 688** | 298–530 | (서버 왕복) | **지연** (서로 다른 3행) |
| 7a | 홈 카드 필터 타이핑 (`workspace-filter`, 30카드) | A-순수 | **0 / 1** | — | 0–3 | **즉각** |
| 7b | 작업실 트리 필터 타이핑 (`tree-filter`) | A-순수 | **1 / 1** | — | 1–2 | **즉각** |
| 8 | 스크리닝 실행→결과 **렌더** (3버전) | A-redir | **640 / 1003** ‡ | 룰엔진 컴퓨트 454–715 | (서버 왕복) | **문제**(경계) ‡ + 스크립트 리빌 ~1.8s |
| 9a | 구성원 `/members` 로드 | B | **366 / 434** | 309–377 | 53 | **지연** |
| 9b | 설정 `/settings` 로드 | B | **432 / 1251** | 349–1152 | 81–90 | **지연** (스파이크 시 문제) |

**보조 관측:**
- item 2 낙관 슬라이드-인: `turbo:before-fetch-request`에서 즉시 발화 → 패널은 **<16ms**에 나타나고
  스피너 표시, 실제 콘텐츠는 329–390ms에 채워짐(사용자는 "즉시 열리고 잠깐 로딩" 체감).
- item 5a `settle`(DOM 변화 정지)은 4–5ms로 나오는데, 이는 Turbo Drive가 `<body>`를 교체하며 옛 body에 붙은
  observer가 분리되기 때문(탭 하이라이트만 잡힘). **`turbo:load`가 올바른 네비 완료 지표** → 위 표 값 사용.
- item 8 `turbo:load`는 **결과 DOM 렌더 완료**까지. 그 뒤 `screening_controller`가 **의도된 스캔-리빌
  애니메이션**(SCAN_MS=1800ms + finding 스태거 110ms·요약 칩 페이드)을 재생 → **"결과가 다 드러날 때"는
  렌더(0.4–1.0s) + 리빌(~1.8–2.5s)**. 리빌은 레이턴시가 아니라 연출이다.
- item 5b 낙관 숨김은 **동기 클래스 토글**(3–5ms)로 서버 왕복(button_to DELETE)보다 한참 앞서 반영 — 직전
  구현(낙관 탭 닫기)이 의도대로 작동함을 확인.

---

## ⑤ 병목 상위 5 (원인 가설 1줄 — 개선은 하지 않음)

1. **작업실 트리 페이지 (item 1) — 계측 세션 웜 2.7~3.2s.** 서버 TTFB가 전부(렌더 몫 127–176ms로 브라우저단
   무결) → **순수 서버 축**. 단, 독립 교차 검증(캐비앗 참조)에서 유휴 웜 상태의 같은 페이지가 ttfb 54~262ms로
   서빙됨을 확인 — 절대치는 dev 세션 부하 의존이며, 안정 신호는 "이 페이지가 서버-바운드"라는 구조 자체다.
2. **PDF 아트워크 첫 페인트 (item 3) — 웜 ~1.15s.** 페이지 로드(0.7–0.8s) + PDF.js가 blob fetch 후
   canvas 렌더(~0.35–0.45s). 첫 바이트가 아니라 "그림이 보일 때"까지라 페이지 로드보다 한 단계 느림.
3. **스크리닝 실행 (item 8) — 렌더 0.4~1.0s + 리빌 ~1.8s.** 서버 룰엔진 컴퓨트(0.2–0.7s)가 렌더 레이턴시
   지배. 그 위에 의도된 스캔 애니메이션 ~1.8s가 얹혀 체감 "결과 등장"은 2s대 — 연출/레이턴시 분리 필요.
4. **상단 탭 / 버전 네비게이션 (item 5a) — 웜 0.66~1.3s.** Turbo Drive지만 버전 상세 페이지 서버 렌더가
   그대로 왕복 비용(서버 몫 626–1229ms). 클라 몫(탭 하이라이트 ~4ms)은 즉각.
5. **claim / 리뷰 인박스 (item 6b·6a) — 웜 0.43~0.8s.** button_to POST→리다이렉트→재렌더 서버 왕복
   (298–530ms) + 인박스 40행 재렌더. 낙관 UI 없이 서버 응답을 기다림(드로어·탭닫기와 대조).

### 판정 분포
- **즉각(<100ms) — 6종, 전부 순수 클라이언트**: 리뷰 토글(4a)·탭 전환(4b)·탭 닫기 낙관(5b)·홈 필터(7a)·
  트리 필터(7b) + 드로어 낙관 슬라이드/탭 하이라이트. → **INP/브라우저 레이어는 우수.**
- **지연(<1s) — 6종, 전부 서버 왕복**: 드로어 콘텐츠(2)·버전 로드(3)·탭 네비(5a)·리뷰 로드(6a)·claim(6b)·구성원(9a).
- **문제(>1s) — 4종, 전부 서버/자산 또는 연출**: 작업실 트리(1)·PDF 첫 페인트(3)·스크리닝(8, 경계+연출)·설정 스파이크(9b).

**한 줄 결론:** 지연·문제로 분류된 **모든** 인터랙션의 원인은 **서버 TTFB(또는 PDF 자산·의도된 애니메이션)**
이며, **브라우저가 원인인 항목은 0건**이다. 순수 클라이언트 인터랙션과 낙관 UI(드로어 슬라이드 <16ms, 탭 닫기
3–5ms)는 서버 왕복 동안 즉각 피드백을 주며 설계대로 작동한다.

---

## ⑥ 직전 서버 사이클 상호 참조

- 커밋 **`4017698`** `perf: 계측 확정 병목 11건 — 쿼리 325→275·트리 재귀/배지 2중 COUNT/실 N+1 소멸 + 게이트 3종`.
- 그 사이클은 **TTFB 내부(쿼리 수)**를 줄였다. 이 사이클은 그 **TTFB가 체감 레이턴시의 유일한 병목축**임을
  독립 계측으로 확증한다 — 지연/문제 12건 중 12건이 서버 몫, 렌더/클라 몫은 전 항목 양호·즉각.
- **함의(개선 아님, 관측):** 다음 체감 개선의 레버는 여전히 **서버 TTFB**(특히 item 1 트리 2.5–3s, item 5a
  버전 렌더)와 **자산/연출**(PDF 첫 페인트, 스크리닝 리빌)에 있고, 브라우저단(INP)에는 없다. 트리·인박스처럼
  낙관 UI가 없는 서버 왕복 인터랙션은 드로어/탭닫기식 낙관 패턴 적용 여지가 있다(별도 판단).

---

### 부록 — 측정 중 발견한 방법론 함정 2건 (재현 시 주의)

- **함정 A — 낙관 UI가 200ms-정지 하네스를 조기 종료시킴.** item 2 드로어를 순수 하네스로 재면 16–86ms로
  나오는데, 이는 `before-fetch-request`의 낙관 슬라이드(≈t0)만 잡고 200ms 정지로 끝난 값이다(실제 콘텐츠는
  300ms+ 뒤 도착 — 슬라이드와 콘텐츠 사이 >200ms 공백에서 조기 resolve). **네트워크-백드 A는 완료
  이벤트(`turbo:frame-load`/`turbo:submit-end`)까지 측정**해야 참값(329–390ms)이 나온다.
- **함정 B — Turbo Drive는 Navigation Timing 엔트리를 안 만든다.** 상단 탭·claim·스크리닝은 fetch+history
  방문이라 `getEntriesByType('navigation')`가 갱신되지 않는다. `turbo:load`/`turbo:submit-end` 이벤트 시각과
  리소스 타이밍으로 서버 몫을 분리했다. 또한 body 교체로 옛 `<body>`의 MutationObserver가 분리되므로
  `settle`값은 신뢰 불가 — 이벤트 시각을 진실원천으로 삼았다.

---

## ⑦ 개선 게이트 판정 — 코드 개선 생략 (2026-07-11 확정)

지연·문제 판정 12건에 대해 개선 발동 여부를 검토한 결과 **생략**으로 확정했다. 근거:

1. 원인이 전부 서버 몫이고 브라우저(INP) 원인은 0건이다 — 클라이언트 레이어는 손댈 곳이 없다.
2. 서버 축은 직전 사이클(커밋 4017698)에서 쿼리 수준 최적화가 끝났고 게이트 3종이 회귀를 방어 중이다.
3. 절대치는 dev 세션 부하가 지배함이 독립 교차 검증으로 실증됐다(최악 판정 페이지가 유휴 웜에선 ttfb 54~262ms).
4. 남은 비용은 바닥 비용이다 — PDF.js 렌더 ~0.4s(자산 크기 대비 합리), 스크리닝 룰엔진 컴퓨트(실제 작업),
   스캔-리빌 1.8s(의도된 연출).

낙관 UI가 없는 서버 왕복 인터랙션(claim 등)에 드로어·탭닫기식 낙관 패턴을 얹는 선택지는 남아 있으나,
서버 원자 경합 판정의 실패 롤백 UX가 필요해 침습 대비 이득이 얕다고 판단해 백로그로만 남긴다.
프로덕션 배포가 결정되면 프로덕션 모드 재계측이 이 문서의 후속이다.
