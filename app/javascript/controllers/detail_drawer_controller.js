import { Controller } from "@hotwired/stimulus"

// 우측 상세 드로어: 프레임(#detail)에 콘텐츠가 로드되면 슬라이드 인, 닫기/Esc 시 슬라이드 아웃 + URL 정리
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.frame = this.element.querySelector("turbo-frame#detail")
    // 열림 상태는 URL(/products/:id) 기준 — 프레임 캐시 잔여로 인한 desync(닫은 드로어 재오픈) 방지
    if (this._productUrl()) this.open()
    this._onLoad = () => this.open()
    this.frame?.addEventListener("turbo:frame-load", this._onLoad)
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    this.frame?.removeEventListener("turbo:frame-load", this._onLoad)
    document.removeEventListener("keydown", this._onKey)
  }

  _productUrl() { return window.location.pathname.startsWith("/products/") }

  open() { this.panelTarget.classList.remove("translate-x-full") }

  close() {
    this.panelTarget.classList.add("translate-x-full")
    if (this.frame) this.frame.replaceChildren()
    // 드로어 닫으면 URL을 대시보드로(현 history.state 보존 — Turbo 복원 캐시 교란 방지)
    if (this._productUrl()) history.replaceState(history.state, "", "/")
  }
}
