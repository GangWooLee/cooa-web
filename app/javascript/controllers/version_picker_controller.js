import { Controller } from "@hotwired/stimulus"

// 버전 페어 선택 → 비교 경로로 이동
export default class extends Controller {
  go() {
    const from = this.element.querySelector("[data-role='from']").value
    const to = this.element.querySelector("[data-role='to']").value
    if (from && to && from !== to) window.location = `/versions/${from}/compare/${to}`
  }
}
