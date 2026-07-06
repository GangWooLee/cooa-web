import { Controller } from "@hotwired/stimulus"

// 버전 aside 탭 스위처(피드백|정보) — 활성 패널만 표시(hidden 토글) + 탭 aria-selected/색(reviews/index 칩 패턴).
// version-feedback 컨트롤러와 완전 독립: 그 타깃(list/detail/newForm)은 건드리지 않고 패널 래퍼만 토글한다.
// hidden(display:none)은 컴파일 CSS에서 flex 뒤에 생성돼 flex를 이긴다 → flex 패널도 확실히 감춰진다.
export default class extends Controller {
  static targets = ["tab", "pane"]

  select(e) {
    const name = e.currentTarget.dataset.pane
    this.tabTargets.forEach((t) => {
      const on = t.dataset.pane === name
      t.setAttribute("aria-selected", String(on))
      t.classList.toggle("bg-cooa", on)
      t.classList.toggle("text-white", on)
      t.classList.toggle("bg-tint", !on)
      t.classList.toggle("text-muted", !on)
    })
    this.paneTargets.forEach((p) => p.classList.toggle("hidden", p.dataset.pane !== name))
  }
}
