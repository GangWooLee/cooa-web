import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["input", "leaf"]
  filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    if (q) this.element.querySelectorAll("details").forEach((d) => (d.open = true))
    this.leafTargets.forEach((l) => {
      l.style.display = !q || (l.dataset.name || "").toLowerCase().includes(q) ? "" : "none"
    })
  }
}
