import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 드로어 슬롯 액션바: 버전 버튼을 슬롯에 드래그앤드롭(또는 클릭) → 비교 a/b·스크리닝 c.
// 비교는 같은 구성요소 두 버전만. [비교 열기]/[스크리닝]으로 실행.
export default class extends Controller {
  static targets = ["slot", "version", "compareBtn", "screenBtn"]

  connect() {
    this.sel = {} // { a|b|c: { id, label, comp } }
    this.active = "a"
    this.render()
    this.element.setAttribute("data-vs-ready", "1") // 연결 완료 신호(테스트 동기화)
  }

  dataOf(el) {
    return { id: el.dataset.vid, label: el.dataset.vlabel, comp: el.dataset.comp }
  }

  // 공통 채우기 — 비교 슬롯(a·b)은 동일 구성요소만(상대 슬롯이 다른 comp면 비움 → 데드엔드 없음)
  fill(slot, v) {
    if (slot === "c") {
      this.sel.c = v
    } else {
      const otherKey = slot === "a" ? "b" : "a"
      if (this.sel[otherKey] && this.sel[otherKey].comp !== v.comp) delete this.sel[otherKey]
      this.sel[slot] = v
    }
    this.render()
  }

  // ── 클릭(접근성 폴백): 비교 쌍 자동 빌드(a→b, 같은 구성요소). 스크리닝은 슬롯 c 활성 후 선택 ──
  activate(e) { this.active = e.currentTarget.dataset.slot; this.render() }
  pick(e) {
    const v = this.dataOf(e.currentTarget)
    this.fill(this.active, v) // 활성 슬롯에 채움(fill이 비교 동일-구성요소 제약 처리)
    if (this.active === "c") this.active = "a"                     // 스크리닝 1회 후 비교 모드 복귀
    else if (this.active === "a" && !this.sel.b) this.active = "b" // 자동 진행
    else if (this.active === "b" && !this.sel.a) this.active = "a" // 리셋되면 a로 복귀(데드엔드 방지)
    this.render()
  }

  // ── 드래그앤드롭 ──
  dragstart(e) {
    e.dataTransfer.setData("text/plain", JSON.stringify(this.dataOf(e.currentTarget)))
    e.dataTransfer.effectAllowed = "copy"
  }
  dragover(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "copy"
    e.currentTarget.classList.add("ring-2", "ring-cooa")
  }
  dragleave(e) {
    if (e.currentTarget.contains(e.relatedTarget)) return // 자식(라벨)로 이동 시 깜빡임 방지
    e.currentTarget.classList.remove("ring-2", "ring-cooa")
  }
  drop(e) {
    e.preventDefault()
    e.currentTarget.classList.remove("ring-2", "ring-cooa")
    let v
    try { v = JSON.parse(e.dataTransfer.getData("text/plain")) } catch { return }
    if (v && v.id) this.fill(e.currentTarget.dataset.slot, v)
  }

  clear(e) { delete this.sel[e.currentTarget.dataset.slot]; this.render() }
  compare() { const { a, b } = this.sel; if (a && b && a.comp === b.comp) Turbo.visit(`/versions/${a.id}/compare/${b.id}`) }
  screen() { if (this.sel.c) Turbo.visit(`/versions/${this.sel.c.id}/screening`) }

  render() {
    this.slotTargets.forEach((s) => {
      const v = this.sel[s.dataset.slot]
      const label = s.querySelector("[data-label]")
      if (label) label.textContent = v ? v.label : "+"
      const isActive = s.dataset.slot === this.active
      s.classList.toggle("border-cooa", !!v || isActive)
      s.classList.toggle("text-cooa", !!v)
      s.classList.toggle("bg-accent", !!v)
    })
    const ids = Object.values(this.sel).map((v) => v.id)
    this.versionTargets.forEach((n) => {
      const on = ids.includes(n.dataset.vid)
      n.classList.toggle("ring-2", on)
      n.classList.toggle("ring-cooa", on)
    })
    const canCompare = this.sel.a && this.sel.b && this.sel.a.comp === this.sel.b.comp
    if (this.hasCompareBtnTarget) this.compareBtnTarget.disabled = !canCompare
    if (this.hasScreenBtnTarget) this.screenBtnTarget.disabled = !this.sel.c
  }
}
