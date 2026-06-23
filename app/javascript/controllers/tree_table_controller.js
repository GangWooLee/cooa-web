import { Controller } from "@hotwired/stimulus"

// 대시보드 트리 테이블: caret 클릭 시 하위 행 접기/펼치기 (pre-order 행 기준)
export default class extends Controller {
  static targets = ["row"]

  connect() {
    this.collapsed = new Set()
  }

  toggle(event) {
    const tr = event.currentTarget.closest("tr")
    if (!tr) return
    const id = tr.dataset.nodeId
    this.collapsed.has(id) ? this.collapsed.delete(id) : this.collapsed.add(id)
    tr.querySelector(".tree-caret")?.classList.toggle("-rotate-90")
    this.update()
  }

  update() {
    let hideBelow = Infinity
    this.rowTargets.forEach((row) => {
      const depth = parseInt(row.dataset.depth, 10)
      if (depth > hideBelow) {
        row.classList.add("hidden")
        return
      }
      row.classList.remove("hidden")
      hideBelow = Infinity
      if (this.collapsed.has(row.dataset.nodeId)) hideBelow = depth
    })
  }
}
