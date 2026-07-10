import { Controller } from "@hotwired/stimulus"

// 좌측 사이드바 접기/펼치기 — desktop은 쿠키 영속, mobile은 오프캔버스 임시 열림.
export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.sync()
  }

  toggle() {
    const root = document.documentElement

    if (this.desktop) {
      root.classList.remove("sidebar-open")
      const collapsed = root.classList.toggle("sidebar-collapsed")
      document.cookie = `cooa_sidebar=${collapsed ? 1 : 0}; path=/; max-age=31536000; samesite=lax`
    } else {
      root.classList.toggle("sidebar-open")
    }

    this.sync()
  }

  close() {
    document.documentElement.classList.remove("sidebar-open")
    this.sync()
  }

  onKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  sync() {
    const root = document.documentElement
    if (this.desktop) root.classList.remove("sidebar-open")

    if (!this.hasToggleTarget) return

    const expanded = this.desktop ? !root.classList.contains("sidebar-collapsed") : root.classList.contains("sidebar-open")
    this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    this.toggleTarget.setAttribute("aria-label", expanded ? "사이드바 닫기" : "사이드바 열기")
  }

  get desktop() {
    return window.matchMedia("(min-width: 1024px)").matches
  }
}
