import { Controller } from "@hotwired/stimulus"

// 전역 flash 토스트 — 자동 소멸(notice 4s · alert 8s) + 수동 ✕ 닫기 + 퇴장 트랜지션(opacity/transform 200ms).
// reduced-motion이면 트랜지션 생략 즉시 제거. 타이머는 disconnect에서 정리(네비 중 분리된 컨트롤러를 건드리지
// 않게 — screening_controller와 동일 규율). 각 토스트가 자기 인스턴스(kind로 수명 결정).
export default class extends Controller {
  static values = { kind: String }

  connect() {
    this._timers = []
    const ms = this.kindValue === "alert" ? 8000 : 4000
    this._timers.push(setTimeout(() => this.close(), ms))
  }

  disconnect() { this._timers.forEach(clearTimeout) }

  close() {
    if (this._closing) return
    this._closing = true
    // reduced-motion: 트랜지션 없이 즉시 제거(.flash-leave CSS도 동일 보장 — 이중 못박기).
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) { this.element.remove(); return }
    this.element.classList.add("flash-leave")
    this._timers.push(setTimeout(() => this.element.remove(), 220))
  }
}
