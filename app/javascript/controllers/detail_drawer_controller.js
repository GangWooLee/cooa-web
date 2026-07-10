import { Controller } from "@hotwired/stimulus"

// 우측 상세 드로어: 프레임(#detail)에 콘텐츠가 로드되면 슬라이드 인, 닫기/Esc 시 슬라이드 아웃 + URL 정리.
// 접근성(a11y-3): 열릴 때 닫기 버튼으로 포커스 이동 · Tab 순환 트랩 · 닫을 때 트리거로 포커스 복원.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.frame = this.element.querySelector("turbo-frame#detail")
    this._open = false
    // 프레임 fetch 시작 즉시 패널 슬라이드-인 + 트리거 저장(닫을 때 포커스 복원용). 로딩 스피너는 CSS([busy]).
    this._onFetch = () => { this._trigger = document.activeElement; this.slideIn() }
    this.frame?.addEventListener("turbo:before-fetch-request", this._onFetch)
    // 콘텐츠(제품명 h1·닫기 버튼) 도착 후에 포커스를 이동해야 하므로 open()은 frame-load에서.
    this._onLoad = () => this.opened()
    this.frame?.addEventListener("turbo:frame-load", this._onLoad)
    this._onKey = (e) => {
      if (e.key === "Escape") this.close()
      else if (e.key === "Tab" && this._open) this.trapTab(e)
    }
    document.addEventListener("keydown", this._onKey)
    // 열림 상태는 URL(/products/:id) 기준 — 프레임 캐시 잔여로 인한 desync(닫은 드로어 재오픈) 방지
    if (this._productUrl()) this.opened()
  }

  disconnect() {
    this.frame?.removeEventListener("turbo:before-fetch-request", this._onFetch)
    this.frame?.removeEventListener("turbo:frame-load", this._onLoad)
    document.removeEventListener("keydown", this._onKey)
  }

  _productUrl() { return window.location.pathname.startsWith("/products/") }

  slideIn() { this.panelTarget.classList.remove("translate-x-full") }

  // 콘텐츠 도착(또는 초기 로드) 시: 슬라이드-인 + 닫기 버튼으로 포커스 이동(모달 진입).
  opened() {
    this.slideIn()
    this._open = true
    const closeBtn = this.panelTarget.querySelector("[data-action~='detail-drawer#close']")
    closeBtn?.focus({ preventScroll: true })
  }

  close() {
    this.panelTarget.classList.add("translate-x-full")
    this._open = false
    if (this.frame) this.frame.replaceChildren()
    // 드로어 닫으면 URL을 대시보드로(현 history.state 보존 — Turbo 복원 캐시 교란 방지)
    if (this._productUrl()) history.replaceState(history.state, "", "/")
    // 포커스를 열기 트리거(트리 행·사이드바 링크)로 복원
    if (this._trigger && document.contains(this._trigger)) this._trigger.focus({ preventScroll: true })
    this._trigger = null
  }

  // Tab 순환 트랩 — aria-modal 배경으로의 탈출을 막는다(inert 미사용, Turbo 프레임 스왑 안전).
  trapTab(e) {
    const f = this.focusables()
    if (!f.length) return
    const first = f[0], last = f[f.length - 1]
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus() }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus() }
  }

  focusables() {
    return Array.from(this.panelTarget.querySelectorAll(
      "a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    )).filter((el) => el.offsetParent !== null)
  }
}
