import { Controller } from "@hotwired/stimulus"
import { bindDismiss, unbindDismiss } from "controllers/lib/dismissable"

// 드롭다운/케밥 메뉴 — 토글 + 바깥클릭/Esc 닫기(공용 dismiss).
// toggle은 stopPropagation으로 부모(행 토글/드로어)로의 버블 차단.
export default class extends Controller {
  static targets = ["panel"]

  connect() { bindDismiss(this) }
  disconnect() { unbindDismiss(this) }

  toggle(e) {
    e.stopPropagation()
    this.panelTarget.classList.toggle("hidden")
  }

  hide() { this.panelTarget.classList.add("hidden") }
}
