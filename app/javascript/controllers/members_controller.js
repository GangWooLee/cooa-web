import { Controller } from "@hotwired/stimulus"

// 담당자 동적 행 — 추가/삭제 후 폼 전체 제출(서버 sync_members가 재구성).
export default class extends Controller {
  static targets = ["rows", "template"]

  add() {
    const node = this.templateTarget.content.firstElementChild.cloneNode(true)
    this.rowsTarget.appendChild(node)
    node.querySelector("input")?.focus()
  }

  remove(e) {
    e.target.closest("[data-members-target='row']")?.remove()
  }

  save() {
    this.element.querySelector("form[data-inline-edit-target='form']")?.requestSubmit()
  }
}
