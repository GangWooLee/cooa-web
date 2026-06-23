import { Controller } from "@hotwired/stimulus"

// 스크리닝: finding 카드 ↔ 아트워크 박스 상호 포커스
export default class extends Controller {
  static targets = ["finding"]

  get viewer() {
    const el = this.element.querySelector("[data-controller~='artwork-viewer']")
    return el && this.application.getControllerForElementAndIdentifier(el, "artwork-viewer")
  }

  onFocus(e) { this.highlight(e.detail.seq) }
  focusFinding(e) { const seq = e.currentTarget.dataset.seq; if (seq) this.viewer?.focus(seq) }

  highlight(seq) {
    this.findingTargets.forEach((f) => {
      const on = f.dataset.seq == seq
      f.classList.toggle("ring-2", on)
      f.classList.toggle("ring-cooa", on)
      if (on) f.scrollIntoView({ block: "nearest", behavior: "smooth" })
    })
  }
}
