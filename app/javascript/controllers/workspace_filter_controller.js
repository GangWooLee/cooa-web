import { Controller } from "@hotwired/stimulus"

// 홈 작업실 카드 간이 필터(서버 왕복 0). 카드의 data-name(작업실명+코드) 부분일치로 보이기/숨기기 +
// 빈 결과 1줄. tree_filter의 축소판(트리·조상펼침 없음 — 평면 카드 그리드).
export default class extends Controller {
  static targets = ["input", "card", "empty"]

  filter() {
    const q = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    let n = 0
    this.cardTargets.forEach((c) => {
      const hit = !q || (c.dataset.name || "").toLowerCase().includes(q)
      c.style.display = hit ? "" : "none"
      if (hit) n++
    })
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", n !== 0)
  }
}
