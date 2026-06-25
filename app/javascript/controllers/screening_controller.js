import { Controller } from "@hotwired/stimulus"

// 스크리닝: finding 카드 ↔ 아트워크 박스 상호 포커스.
// 방금 실행(justRan)이면 (a) 스캔 빔 → (b) 결과 카드 순차 reveal(blur→clear) → (c) 박스 seq 순서 reveal.
export default class extends Controller {
  static targets = ["finding", "scanner"]
  static values = { justRan: Boolean }

  connect() {
    this._timers = []
    if (this.justRanValue) this.runReveal()
  }

  disconnect() { this._timers.forEach(clearTimeout) } // 네비 중 setTimeout이 분리된 컨트롤러를 건드리지 않게

  _after(ms, fn) {
    this._timers.push(setTimeout(() => { if (this.element.isConnected) fn() }, ms))
  }

  get viewer() {
    const el = this.element.querySelector("[data-controller~='artwork-viewer']")
    return el && this.application.getControllerForElementAndIdentifier(el, "artwork-viewer")
  }

  get boxes() {
    return Array.from(this.element.querySelectorAll("[data-artwork-viewer-target='box']"))
  }

  runReveal() {
    const SCAN_MS = 1800 // 라인 통과 시간(CSS --scan-ms와 동기화 — 단일 출처)
    this.element.style.setProperty("--scan-ms", `${SCAN_MS}ms`)
    if (this.hasScannerTarget) this.scannerTarget.classList.remove("hidden")

    // (a) 박스: 라인의 선명선이 box_y를 지나는 순간 감지 reveal(인라인 opacity가 scanning CSS를 덮음)
    const bx = this.boxes
    bx.forEach((b) => { b.style.opacity = "0"; b.style.transform = "scale(.92)"; b.style.transition = "opacity .3s ease, transform .3s ease" })
    bx.forEach((b) => {
      const y = parseFloat(b.dataset.y) || 0
      this._after((y / 100) * SCAN_MS, () => { b.style.opacity = "1"; b.style.transform = "scale(1)" })
    })

    // (b) 패스 종료: 라인 숨김 + scanning 해제 + 남은 박스 보장 + 결과 카드 위→아래 순차
    this._after(SCAN_MS, () => {
      if (this.hasScannerTarget) this.scannerTarget.classList.add("hidden")
      this.element.querySelector(".screening-scanning")?.classList.remove("screening-scanning")
      bx.forEach((b) => { b.style.opacity = "1"; b.style.transform = "scale(1)" }) // 누락 방지
      this.findingTargets.forEach((f, i) => {
        f.style.transition = "opacity .4s ease, filter .4s ease"
        this._after(i * 110, () => f.classList.remove("opacity-0", "blur-[2px]"))
      })
    })
  }

  onFocus(e) { this.highlight(e.detail.seq) }
  focusFinding(e) { const seq = e.currentTarget.dataset.seq; if (seq) this.viewer?.focus(seq) }

  highlight(seq) {
    this.findingTargets.forEach((f) => {
      const on = f.dataset.seq == seq
      f.classList.toggle("ring-2", on)
      f.classList.toggle("ring-cooa", on)
      if (on) f.scrollIntoView({ block: "nearest", behavior: "smooth" })
    })
  }
}
