// 전역 네트워크/Turbo 실패 토스트(E5 · docs/error-handling.md). 레이아웃 flash(alert)와 동일한 결의
// 수동 닫기 토스트를 띄운다. 두 경로에서 호출: (1) Turbo 구동 요청의 전역 실패
// (turbo:fetch-request-error · turbo:frame-missing) — 이 모듈이 import 시 리스너 설치, (2) 수동 fetch의
// catch 경로(tree_dnd·sortable)에서 showNetErrorToast() 직접 호출. CSP는 style_src를 제한하지 않으므로
// 인라인 스타일 허용(색상은 application.css의 warn/tint/ink 토큰과 동일 값).

const MESSAGE = "네트워크 오류 — 잠시 후 다시 시도해주세요."

function container() {
  let el = document.getElementById("cooa-net-toasts")
  if (!el) {
    el = document.createElement("div")
    el.id = "cooa-net-toasts"
    el.setAttribute("aria-live", "polite")
    el.style.cssText =
      "position:fixed;top:16px;left:50%;transform:translateX(-50%);z-index:60;" +
      "display:flex;flex-direction:column;gap:8px;width:min(92vw,28rem);pointer-events:none"
    document.body.appendChild(el)
  }
  return el
}

export function showNetErrorToast(message = MESSAGE) {
  const host = container()
  // 중복 폭주 방지: 동일 메시지 토스트가 이미 떠 있으면 새로 만들지 않음.
  if ([ ...host.children ].some((c) => c.dataset.msg === message)) return

  const toast = document.createElement("div")
  toast.dataset.msg = message
  toast.setAttribute("role", "alert")
  toast.style.cssText =
    "pointer-events:auto;display:flex;align-items:flex-start;gap:12px;" +
    "border:1px solid #e6a700;background:#f5f5f5;color:#3d3d3d;border-radius:12px;" +
    "padding:12px 14px;font-size:13px;font-weight:500;box-shadow:0 6px 20px rgba(0,0,0,.12)"

  const text = document.createElement("span")
  text.textContent = message
  text.style.flex = "1"

  const close = document.createElement("button")
  close.type = "button"
  close.setAttribute("aria-label", "닫기")
  close.textContent = "×" // ×
  close.style.cssText =
    "cursor:pointer;border:0;background:transparent;color:#3d3d3d;font-size:16px;line-height:1;padding:0;margin:0"
  close.addEventListener("click", () => toast.remove())

  toast.append(text, close)
  host.appendChild(toast)
}

// Turbo 구동 요청의 전역 실패 → 토스트. 기본 동작은 보존(preventDefault 하지 않음).
function install() {
  if (window.__cooaNetToastInstalled) return
  window.__cooaNetToastInstalled = true
  document.addEventListener("turbo:fetch-request-error", () => showNetErrorToast())
  document.addEventListener("turbo:frame-missing", () => showNetErrorToast())
}

install()
