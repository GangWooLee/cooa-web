import { Controller } from "@hotwired/stimulus"

// 구성요소 버전 타임라인: 연결선 ▾ 클릭 시 변경사유 패널 펼침/접힘 (아코디언 — 행당 1개만 열림)
export default class extends Controller {
  static targets = ["dot", "panel"]

  toggle(e) {
    const idx = String(e.params.index)
    const panel = this.panelTargets.find((p) => p.dataset.index === idx)
    if (!panel) return
    const willOpen = panel.classList.contains("hidden")

    this.panelTargets.forEach((p) => p.classList.add("hidden"))
    this.dotTargets.forEach((d) => {
      d.classList.remove("rotate-180", "border-cooa", "bg-accent", "text-cooa")
      d.setAttribute("aria-expanded", "false")
    })

    if (willOpen) {
      panel.classList.remove("hidden")
      const dot = this.dotTargets.find((d) => d.dataset.index === idx)
      if (dot) {
        dot.classList.add("rotate-180", "border-cooa", "bg-accent", "text-cooa")
        dot.setAttribute("aria-expanded", "true")
      }
    }
  }
}
