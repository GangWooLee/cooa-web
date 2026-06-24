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
    const SCAN_MS = 1600 // 스캔 빔 지속(CSS scan-beam 1.5s가 ~1회 순회)
    if (this.hasScannerTarget) this.scannerTarget.classList.remove("hidden")
    this._after(SCAN_MS, () => {
      if (this.hasScannerTarget) this.scannerTarget.classList.add("hidden")
      this.element.querySelector(".screening-scanning")?.classList.remove("screening-scanning")

      // (b) 결과 카드 순차 reveal — blur→clear, 130ms 간격
      this.findingTargets.forEach((f, i) => {
        f.style.transition = "opacity .45s ease, filter .45s ease"
        this._after(i * 130, () => f.classList.remove("opacity-0", "blur-[2px]"))
      })

      // (c) 박스 seq 순서 reveal — 인라인 제어로 stagger(자연스러운 scale-in)
      const bx = this.boxes
      bx.forEach((b) => { b.style.opacity = "0"; b.style.transform = "scale(.9)"; b.style.transition = "opacity .4s ease, transform .4s ease" })
      bx.forEach((b, i) => this._after(150 + i * 160, () => { b.style.opacity = "1"; b.style.transform = "scale(1)" }))
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
