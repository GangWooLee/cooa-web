import { Controller } from "@hotwired/stimulus"

// 구성요소 버전 타임라인: 연결선 ▾ 클릭 시 변경사유 패널 펼침/접힘 (아코디언 — 행당 1개만 열림)
export default class extends Controller {
  static targets = ["dot", "panel", "track"]

  // 좁은 폭에서 현재(active) 버전 칩이 우측 화면 밖으로 잘리므로, 연결 시 그 칩(+새 버전 버튼)이
  // 보이도록 트랙을 가로 스크롤(scrollLeft)한다 — 페이지 세로 스크롤을 유발하지 않는 수평 전용 조정(layout-2).
  connect() {
    if (!this.hasTrackTarget) return
    const track = this.trackTarget
    const cur = track.querySelector("[data-current]")
    if (!cur) return
    const target = cur.offsetLeft + cur.offsetWidth - track.clientWidth + 28 // +새 버전 버튼 여지
    if (target > 0) track.scrollLeft = target
  }

  toggle(e) {
    const idx = String(e.params.index)
    const panel = this.panelTargets.find((p) => p.dataset.index === idx)
    if (!panel) return
    const willOpen = panel.classList.contains("hidden")

    this.panelTargets.forEach((p) => p.classList.add("hidden"))
    this.dotTargets.forEach((d) => {
      d.classList.remove("rotate-180", "dot-on")
      d.setAttribute("aria-expanded", "false")
    })

    if (willOpen) {
      panel.classList.remove("hidden")
      const dot = this.dotTargets.find((d) => d.dataset.index === idx)
      if (dot) {
        dot.classList.add("rotate-180", "dot-on")
        dot.setAttribute("aria-expanded", "true")
      }
    }
  }
}
