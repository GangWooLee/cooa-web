import { Controller } from "@hotwired/stimulus"

// 단일 버전 뷰: 뷰어 박스 focus → 해당 피드백 상세 패널, Shift+드래그(draw) → 새 피드백 폼.
// comparison_controller와 동일 패턴(선형 단일 pane). 리뷰 패널은 정적이라 여기서 다루지 않음.
export default class extends Controller {
  static targets = ["list", "detail", "newForm", "newX", "newY", "newW", "newH"]

  get viewer() {
    const el = this.element.querySelector("[data-controller~='artwork-viewer']")
    return el && this.application.getControllerForElementAndIdentifier(el, "artwork-viewer")
  }

  onFocus(e) {
    if (e.detail.seq == null) this.backToList()
    else this.show(e.detail.seq)
  }
  focusFromList(e) { this.viewer?.focus(e.currentTarget.dataset.seq) }

  show(seq) {
    this.listTarget.style.display = "none"
    if (this.hasNewFormTarget) this.newFormTarget.style.display = "none"
    this.detailTargets.forEach((d) => (d.style.display = d.dataset.seq == seq ? "flex" : "none"))
  }

  backToList() {
    this.detailTargets.forEach((d) => (d.style.display = "none"))
    if (this.hasNewFormTarget) this.newFormTarget.style.display = "none"
    this.listTarget.style.display = "flex"
  }

  onDraw(e) {
    const { x, y, w, h } = e.detail
    if (this.hasNewXTarget) {
      this.newXTarget.value = x.toFixed(2); this.newYTarget.value = y.toFixed(2)
      this.newWTarget.value = w.toFixed(2); this.newHTarget.value = h.toFixed(2)
    }
    this.listTarget.style.display = "none"
    this.detailTargets.forEach((d) => (d.style.display = "none"))
    if (this.hasNewFormTarget) this.newFormTarget.style.display = "flex"
  }
}
