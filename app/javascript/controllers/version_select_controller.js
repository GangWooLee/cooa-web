import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 드로어 슬롯 액션바: 버전 노드 클릭 → 활성 슬롯(비교 a/b·스크리닝 c) 채움.
// 비교는 같은 구성요소 두 버전만. [비교 열기]/[스크리닝]으로 실행.
export default class extends Controller {
  static targets = ["slot", "version", "compareBtn", "screenBtn"]

  connect() {
    this.sel = {}     // { a|b|c: { id, label, comp } }
    this.active = "a" // 기본 활성 슬롯
    this.render()
  }

  activate(e) {
    this.active = e.currentTarget.dataset.slot
    this.render()
  }

  pick(e) {
    const d = e.currentTarget.dataset
    const v = { id: d.vid, label: d.vlabel, comp: d.comp }
    if (this.active === "c") {
      this.sel.c = v
    } else {
      // 비교 슬롯(a·b)은 동일 구성요소만
      const other = this.active === "a" ? this.sel.b : this.sel.a
      if (other && other.comp !== v.comp) {
        // 다른 구성요소 선택 → 새 비교쌍 시작(이 버전을 A로, 활성 B로). 데드엔드 방지
        delete this.sel.b
        this.sel.a = v
        this.active = "b"
      } else {
        this.sel[this.active] = v
        if (this.active === "a") this.active = "b" // 자동 진행
      }
    }
    this.render()
  }

  clear(e) {
    delete this.sel[e.currentTarget.dataset.slot]
    this.render()
  }

  compare() {
    const { a, b } = this.sel
    if (a && b && a.comp === b.comp) Turbo.visit(`/versions/${a.id}/compare/${b.id}`)
  }

  screen() {
    if (this.sel.c) Turbo.visit(`/versions/${this.sel.c.id}/screening`)
  }

  render() {
    this.slotTargets.forEach((s) => {
      const slot = s.dataset.slot
      const v = this.sel[slot]
      const label = s.querySelector("[data-label]")
      if (label) label.textContent = v ? v.label : "+"
      const isActive = slot === this.active
      s.classList.toggle("border-cooa", !!v || isActive)
      s.classList.toggle("text-cooa", !!v)
      s.classList.toggle("bg-accent", !!v)
      s.classList.toggle("ring-2", isActive)
      s.classList.toggle("ring-cooa/40", isActive)
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
