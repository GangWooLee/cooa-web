import { Controller } from "@hotwired/stimulus"
import { bindDismiss, unbindDismiss } from "controllers/lib/dismissable"

// "사람 추가" 입력의 제안 드롭다운(서버 렌더 목록 — 동료 즉시추가 ⓐ + 이전 초대 ⓑ). 포커스=열림 · 타이핑=부분
// 일치 필터(client, data-search) · 클릭/↑↓+Enter=이메일 채움 · Esc/바깥클릭=닫힘(dismissable 재사용). 서버
// (/workspace_memberships)가 최종 분기하므로 목록은 편의 제안일 뿐 자유 입력을 막지 않는다. role=combobox/
// listbox/option · aria-expanded 갱신(접근성). 필터로 숨김은 inline display(Tailwind display 유틸 충돌 회피 —
// workspace_filter와 동형).
export default class extends Controller {
  static targets = ["input", "list", "option"]

  connect() {
    this.active = -1
    this.isOpen = false
    // aria-activedescendant 연결용 고유 id — 스크린리더가 ↑↓ 활성 옵션을 읽는 유일한 채널(ARIA combobox 패턴).
    this.optionTargets.forEach((o, i) => { if (!o.id) o.id = `member-suggest-opt-${i}` })
    bindDismiss(this)
  }

  disconnect() {
    unbindDismiss(this)
  }

  // 포커스 진입 = 제안 열기(있으면).
  open() {
    this.filter()
  }

  // 타이핑 = 부분일치 필터. 매치 0건이면 목록을 닫아(레이아웃 위 오버레이 제거) 아래 역할/버튼 클릭을 가리지 않는다.
  filter() {
    const q = this.inputTarget.value.trim().toLowerCase()
    let shown = 0
    this.optionTargets.forEach((o) => {
      const hit = (o.dataset.search || "").includes(q)
      o.style.display = hit ? "" : "none"
      if (hit) shown++
    })
    this.active = -1
    this.paint()
    this.toggle(shown > 0)
  }

  // 옵션 클릭 = 이메일 채움 + 닫기(옵션은 combobox 내부라 dismissable 바깥클릭에 안 걸림).
  choose(e) {
    this.pick(e.currentTarget)
  }

  keydown(e) {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault()
      this.open()
      const vis = this.visibleOptions()
      if (!vis.length) return
      this.active = (this.active + (e.key === "ArrowDown" ? 1 : -1) + vis.length) % vis.length
      this.paint(vis)
    } else if (e.key === "Enter") {
      const vis = this.visibleOptions()
      if (this.isOpen && this.active >= 0 && vis[this.active]) {
        e.preventDefault() // 활성 옵션 선택 시에만 제출 억제 — 활성 없으면 자유 입력 그대로 제출(서버가 분기).
        this.pick(vis[this.active])
      }
    }
  }

  // dismissable(바깥클릭/Esc) → 목록만 닫는다(모달 Esc 닫힘은 <dialog> native가 별개로 처리).
  hide() {
    this.toggle(false)
  }

  // ── helpers ──
  pick(option) {
    this.inputTarget.value = option.dataset.email
    this.toggle(false)
  }

  visibleOptions() {
    return this.optionTargets.filter((o) => o.style.display !== "none")
  }

  paint(vis = this.visibleOptions()) {
    this.optionTargets.forEach((o) => {
      o.setAttribute("aria-selected", "false")
      o.classList.remove("bg-tint")
    })
    const cur = this.active >= 0 ? vis[this.active] : null
    if (cur) {
      cur.setAttribute("aria-selected", "true")
      cur.classList.add("bg-tint")
      cur.scrollIntoView({ block: "nearest" })
      this.inputTarget.setAttribute("aria-activedescendant", cur.id)
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  toggle(show) {
    this.isOpen = show && this.hasListTarget
    if (this.hasListTarget) this.listTarget.classList.toggle("hidden", !this.isOpen)
    this.inputTarget.setAttribute("aria-expanded", this.isOpen ? "true" : "false")
    if (!this.isOpen) this.inputTarget.removeAttribute("aria-activedescendant")
  }
}
