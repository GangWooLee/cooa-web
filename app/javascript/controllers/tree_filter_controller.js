import { Controller } from "@hotwired/stimulus"

// 사이드바 트리 검색(서버 왕복 0 · 클라이언트 필터). 렌더된 DOM에서 leaf(품목명·코드)와 folder(폴더명)를
// 부분일치로 걸러 보여준다. 접힌 <details> 속 매치가 안 보이던 갭을 메운다 —
//   · 매치의 조상 <details>를 자동 펼침(원래 open 상태를 스냅샷 → 필터 해제 시 복원, 토글 오염 없음)
//   · 폴더명도 매치 대상(이전엔 leaf만)
//   · 매치 카운트("N건") · ✕/Esc 클리어 · 빈 결과 1줄
export default class extends Controller {
  static targets = ["input", "leaf", "count", "clear", "empty"]

  filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    if (!q) return this.reset()
    if (!this.snapshot) this.capture() // 필터 진입 시점(빈→비어있지않음)의 open 상태를 1회만 기억

    const show = new Set() // 표시할 <details>
    const open = new Set() // 펼칠(매치를 품은) <details>
    let n = 0

    // leaf: data-name("품목명 코드") 부분일치. 매치면 그 leaf의 모든 조상 폴더를 펼침+표시(매치 가시화).
    this.leafTargets.forEach((l) => {
      const hit = (l.dataset.name || "").toLowerCase().includes(q)
      l.style.display = hit ? "" : "none"
      if (!hit) return
      n++
      for (let d = l.closest("details"); d; d = d.parentElement.closest("details")) { show.add(d); open.add(d) }
    })

    // folder: summary의 폴더명 부분일치. 자신은 표시(조상은 펼침) — 하위에 매치가 없으면 접힌 채로 둔다
    // (open은 leaf/하위 매치가 있을 때만 부여됨).
    const all = this.element.querySelectorAll("details")
    all.forEach((d) => {
      const name = (d.querySelector(":scope > summary")?.dataset.nodeName || "").toLowerCase()
      if (!name.includes(q)) return
      n++
      show.add(d)
      for (let p = d.parentElement.closest("details"); p; p = p.parentElement.closest("details")) { show.add(p); open.add(p) }
    })

    all.forEach((d) => { d.style.display = show.has(d) ? "" : "none"; d.open = open.has(d) })
    this.paint(n)
  }

  // 필터 해제: 스냅샷 open 상태 복원 + 전체 표시 + 보조 UI 숨김.
  reset() {
    if (this.snapshot) { this.snapshot.forEach((wasOpen, d) => { d.open = wasOpen }); this.snapshot = null }
    this.leafTargets.forEach((l) => (l.style.display = ""))
    this.element.querySelectorAll("details").forEach((d) => (d.style.display = ""))
    if (this.hasCountTarget) this.countTarget.classList.add("hidden")
    if (this.hasEmptyTarget) this.emptyTarget.classList.add("hidden")
    if (this.hasClearTarget) this.clearTarget.classList.add("hidden")
  }

  clear() {
    this.inputTarget.value = ""
    this.reset()
    this.inputTarget.focus()
  }

  keydown(e) {
    if (e.key === "Escape") this.clear()
  }

  capture() {
    this.snapshot = new Map()
    this.element.querySelectorAll("details").forEach((d) => this.snapshot.set(d, d.open))
  }

  paint(n) {
    if (this.hasClearTarget) this.clearTarget.classList.remove("hidden")
    if (this.hasCountTarget) {
      this.countTarget.textContent = `${n}건`
      this.countTarget.classList.toggle("hidden", n === 0)
    }
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", n !== 0)
  }
}
