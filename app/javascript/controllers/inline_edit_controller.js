import { Controller } from "@hotwired/stimulus"

// 인라인 이름변경 — 텍스트 클릭(또는 생성 직후 auto)으로 입력칸 전환, Enter 저장 / Esc 취소 / blur 저장.
export default class extends Controller {
  static targets = ["display", "form", "input"]
  static values = { auto: Boolean }

  connect() {
    if (this.autoValue) this.edit()
  }

  edit() {
    this._done = false
    this.displayTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    if (this.hasInputTarget) { // 담당자 폼처럼 단일 input이 없을 수 있음
      this._original = this.inputTarget.value // 무변경 판별용
      this.inputTarget.focus()
      this.inputTarget.select?.() // <select>에는 없음 — 가드
      this.inputTarget.scrollIntoView({ block: "nearest" }) // 트리 인라인 생성 시 새 행 보이게
    }
  }

  keydown(e) {
    // stopPropagation: Esc가 드로어(document) 닫힘 리스너로 전파되지 않게(이름변경만 취소)
    if (e.key === "Enter") { e.preventDefault(); e.stopPropagation(); this.save() }
    else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); this.cancel() }
  }

  // 사이드바 폴더 <summary> 안의 입력칸 클릭이 details 토글로 전파되지 않게
  stop(e) { e.stopPropagation() }

  // select/date는 변경 즉시 저장
  change() { this.save() }

  // Enter/blur/change 이중제출 방지(_done). 빈값 가드는 text 입력에만(select "—" 비우기 허용).
  // 값 무변경이면 제출 안 함 — 그냥 다른 필드 클릭 시 불필요한 PATCH·풀리렌더(깜빡임) 방지.
  save() {
    if (this._done) return
    const el = this.inputTarget
    if (el.tagName === "INPUT" && el.type === "text" && el.value.trim() === "") { this.cancel(); return }
    if (el.value === this._original) { this.cancel(); return }
    this._done = true
    this.formTarget.requestSubmit()
  }

  cancel() {
    this._done = true // 취소 후 blur가 저장 안 되게
    this.formTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
  }
}
