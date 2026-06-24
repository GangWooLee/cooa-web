import { Controller } from "@hotwired/stimulus"

// 드롭다운/케밥 메뉴 — 토글 + 바깥클릭/Esc 닫기.
// toggle은 stopPropagation으로 부모(행 토글/드로어)로의 버블 차단.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this._out = (e) => { if (!this.element.contains(e.target)) this.hide() }
    this._esc = (e) => { if (e.key === "Escape") this.hide() }
    document.addEventListener("click", this._out)
    document.addEventListener("keydown", this._esc)
  }

  disconnect() {
    document.removeEventListener("click", this._out)
    document.removeEventListener("keydown", this._esc)
  }

  toggle(e) {
    e.stopPropagation()
    this.panelTarget.classList.toggle("hidden")
  }

  hide() { this.panelTarget.classList.add("hidden") }
}
