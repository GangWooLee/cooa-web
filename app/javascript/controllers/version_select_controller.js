import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 드로어 슬롯 액션바: 버전 버튼을 슬롯에 드래그앤드롭으로 채우고, 슬롯 클릭으로 비움.
// 비교는 같은 구성요소 두 버전만. [비교 열기]/[스크리닝]으로 실행.
export default class extends Controller {
  static targets = ["slot", "version", "compareBtn", "screenBtn"]

  connect() {
    this.sel = {} // { a|b|c: { id, label, comp } }
    this.render()
    this.element.setAttribute("data-vs-ready", "1") // 연결 완료 신호(테스트 동기화)
  }

  dataOf(el) {
    return { id: el.dataset.vid, label: el.dataset.vlabel, comp: el.dataset.comp }
  }

  // 채우기 — 비교 슬롯(a·b)은 동일 구성요소만(상대 슬롯이 다른 comp면 비움)
  fill(slot, v) {
    if (!v || !v.id) return // 비정상 값(슬롯 c 포함) 방지 → render/screen의 .id 역참조 안전
    if (slot === "c") {
      this.sel.c = v
    } else {
      const otherKey = slot === "a" ? "b" : "a"
      if (this.sel[otherKey] && this.sel[otherKey].comp !== v.comp) delete this.sel[otherKey]
      this.sel[slot] = v
    }
    this.render()
  }

  // ── 드래그앤드롭(채움) ──
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

  // 버전 노드 클릭 → 해당 버전 파일 전체 페이지로(드로어 프레임 탈출). 드래그 시엔 click 미발화.
  view(e) { Turbo.visit(`/versions/${e.currentTarget.dataset.vid}`) }

  // 담기(+) 클릭 → 다음 빈 비교 슬롯(a→b) 채움. 터치패드 등 드래그가 번거로운 환경의 폴백(드래그와 병존).
  quickFill(e) {
    const slot = !this.sel.a ? "a" : (!this.sel.b ? "b" : "a") // a→b 순서, 둘 다 차면 a부터 갱신
    this.fill(slot, this.dataOf(e.currentTarget))
  }

  // 슬롯 클릭 → 비우기(초기화)
  clear(e) { delete this.sel[e.currentTarget.dataset.slot]; this.render() }
  compare() { const { a, b } = this.sel; if (a && b && a.comp === b.comp) Turbo.visit(`/versions/${a.id}/compare/${b.id}`) }
  screen() { if (this.sel.c) Turbo.visit(`/versions/${this.sel.c.id}/screening`) }

  render() {
    this.slotTargets.forEach((s) => {
      const v = this.sel[s.dataset.slot]
      const label = s.querySelector("[data-label]")
      if (label) label.textContent = v ? v.label : "+"
      s.title = v ? "클릭하여 비우기" : "버전을 여기로 드래그"
      s.classList.toggle("border-cooa", !!v)
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
