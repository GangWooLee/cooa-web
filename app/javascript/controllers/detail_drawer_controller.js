import { Controller } from "@hotwired/stimulus"

// 우측 상세 드로어: 프레임(#detail)에 콘텐츠가 로드되면 슬라이드 인, 닫기/Esc 시 슬라이드 아웃 + URL 정리
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.frame = this.element.querySelector("turbo-frame#detail")
    // 직접 URL 진입 등으로 콘텐츠가 이미 있으면 열기
    if (this.frame && this.frame.children.length > 0) this.open()
    this._onLoad = () => this.open()
    this.frame?.addEventListener("turbo:frame-load", this._onLoad)
    this._onKey = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    this.frame?.removeEventListener("turbo:frame-load", this._onLoad)
    document.removeEventListener("keydown", this._onKey)
  }

  open() { this.panelTarget.classList.remove("translate-x-full") }

  close() {
    this.panelTarget.classList.add("translate-x-full")
    if (this.frame) this.frame.replaceChildren()
    if (window.location.pathname.startsWith("/products/")) history.replaceState({}, "", "/")
  }
}
