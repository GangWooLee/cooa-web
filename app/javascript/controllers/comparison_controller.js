import { Controller } from "@hotwired/stimulus"

// 버전 비교: 뷰어 박스 focus → 해당 어노테이션 상세 패널 전환, draw → 새 피드백 폼
export default class extends Controller {
  static targets = ["list", "detail", "newForm", "newX", "newY", "newW", "newH"]

  get viewer() {
    const el = this.element.querySelector("[data-controller~='artwork-viewer']")
    return el && this.application.getControllerForElementAndIdentifier(el, "artwork-viewer")
  }

  onFocus(e) {
    if (e.detail.seq == null) this.backToList() // 박스 재클릭(토글 해제·무선택) → 리스트로
    else this.show(e.detail.seq)
  }
  focusFromList(e) { this.viewer?.focus(e.currentTarget.dataset.seq) } // → onFocus

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
    if (this.hasNewFormTarget) this.newFormTarget.style.display = "flex" // 다른 참조와 동일하게 가드
  }
}
