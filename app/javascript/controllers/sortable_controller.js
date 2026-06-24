import { Controller } from "@hotwired/stimulus"

// 드래그 순서변경(HTML5 DnD) — 좌측 핸들로 잡아 끌고, 행 위 드롭. drop 후 순서 PATCH.
// _active 가드: 다른 드래그(버전 슬롯 등)와 섞이지 않게.
export default class extends Controller {
  static targets = ["item"]
  static values = { url: String }

  dragstart(e) {
    this._active = true
    this.dragId = e.currentTarget.closest("[data-sortable-target='item']")?.dataset.id
    e.dataTransfer.effectAllowed = "move"
    e.dataTransfer.setData("text/plain", this.dragId || "")
  }

  dragover(e) {
    if (!this._active) return
    e.preventDefault()
    const rect = e.currentTarget.getBoundingClientRect()
    const after = e.clientY - rect.top > rect.height / 2
    this._clear()
    e.currentTarget.classList.add(after ? "drop-after" : "drop-before")
  }

  dragleave(e) {
    if (e.currentTarget.contains(e.relatedTarget)) return
    e.currentTarget.classList.remove("drop-before", "drop-after")
  }

  drop(e) {
    if (!this._active) return
    e.preventDefault()
    this._clear()
    const dragged = this.itemTargets.find((i) => i.dataset.id === this.dragId)
    const target = e.currentTarget
    if (dragged && dragged !== target) {
      const rect = target.getBoundingClientRect()
      const after = e.clientY - rect.top > rect.height / 2
      target.parentNode.insertBefore(dragged, after ? target.nextSibling : target)
      this._persist()
    }
    this._active = false
  }

  dragend() { this._active = false; this._clear() }

  _clear() { this.itemTargets.forEach((i) => i.classList.remove("drop-before", "drop-after")) }

  _persist() {
    const ids = this.itemTargets.map((i) => i.dataset.id)
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(this.urlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      body: JSON.stringify({ ids })
    })
  }
}
