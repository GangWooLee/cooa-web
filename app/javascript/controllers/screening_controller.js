import { Controller } from "@hotwired/stimulus"

// 스크리닝: finding 카드 ↔ 아트워크 박스 상호 포커스.
// 방금 실행(justRan)이면 (a) 우패널 라벨 "스크리닝 중…" + 스캔 빔 → (b) 결과 카드 순차 reveal(blur→clear)
// → (c) 박스 seq 순서 reveal + 판정 요약 칩 페이드인 + 라벨 "스크리닝 결과". 재실행 제출 시 기존 결과 페이드아웃.
// prefers-reduced-motion이면 연출을 전부 생략하고 즉시 전체 표시한다.
export default class extends Controller {
  static targets = ["finding", "scanner", "summary", "label"]
  static values = { justRan: Boolean }

  connect() {
    this._timers = []
    if (!this.justRanValue) { this.clearRerunFade(); return }
    if (this._reduced) this.revealNow()
    else this.runReveal()
  }

  // Turbo bfcache 방어: 재실행 페이드아웃(onRerun) 상태로 캐시된 스냅샷이 Back으로 복원되면 결과가
  // 비가시로 남는다 — justRan 없는 재연결에서 인라인 opacity 잔존물을 정리해 즉시 복원한다.
  clearRerunFade() {
    this.findingTargets.forEach((f) => { f.style.opacity = ""; f.style.transition = "" })
    if (this.hasSummaryTarget) { this.summaryTarget.style.opacity = ""; this.summaryTarget.style.transition = "" }
  }

  disconnect() { this._timers.forEach(clearTimeout) } // 네비 중 setTimeout이 분리된 컨트롤러를 건드리지 않게

  get _reduced() { return window.matchMedia("(prefers-reduced-motion: reduce)").matches }

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

  // reduced-motion: 스캔/스태거/라벨 스왑 없이 즉시 전체 표시(결과 카드·박스·요약 칩 모두 노출). 라벨은 서버가
  // 이미 "스크리닝 결과"로 렌더하므로 손대지 않는다.
  revealNow() {
    this.element.querySelector(".screening-scanning")?.classList.remove("screening-scanning")
    this.boxes.forEach((b) => { b.style.opacity = "1"; b.style.transform = "none" })
    this.findingTargets.forEach((f) => f.classList.remove("opacity-0", "blur-[2px]"))
    if (this.hasSummaryTarget) this.summaryTarget.classList.remove("opacity-0")
  }

  runReveal() {
    const SCAN_MS = 1800 // 라인 통과 시간(CSS --scan-ms와 동기화 — 단일 출처)
    this.element.style.setProperty("--scan-ms", `${SCAN_MS}ms`)
    if (this.hasScannerTarget) this.scannerTarget.classList.remove("hidden")
    if (this.hasLabelTarget) this.labelTarget.textContent = "스크리닝 중…" // 스캔 동안 라이브 라벨

    // (a) 박스: 라인의 선명선이 box_y를 지나는 순간 감지 reveal(인라인 opacity가 scanning CSS를 덮음)
    const bx = this.boxes
    bx.forEach((b) => { b.style.opacity = "0"; b.style.transform = "scale(.92)"; b.style.transition = "opacity .3s ease, transform .3s ease" })
    bx.forEach((b) => {
      const y = parseFloat(b.dataset.y) || 0
      this._after((y / 100) * SCAN_MS, () => { b.style.opacity = "1"; b.style.transform = "scale(1)" })
    })

    // (b) 패스 종료: 라인 숨김 + scanning 해제 + 남은 박스 보장 + 결과 카드 위→아래 순차 → (c) 요약 칩·라벨 복귀
    this._after(SCAN_MS, () => {
      if (this.hasScannerTarget) this.scannerTarget.classList.add("hidden")
      this.element.querySelector(".screening-scanning")?.classList.remove("screening-scanning")
      bx.forEach((b) => { b.style.opacity = "1"; b.style.transform = "scale(1)" }) // 누락 방지
      this.findingTargets.forEach((f, i) => {
        f.style.transition = "opacity .4s ease, filter .4s ease"
        this._after(i * 110, () => f.classList.remove("opacity-0", "blur-[2px]"))
      })
      // (c) 판정 요약 칩: 카드 스태거 뒤 페이드인 + 우패널 라벨을 "스크리닝 결과"로 복귀(둘 다 마지막 카드 뒤)
      const tail = this.findingTargets.length * 110
      if (this.hasSummaryTarget) {
        this.summaryTarget.style.transition = "opacity .2s ease"
        this._after(tail, () => this.summaryTarget.classList.remove("opacity-0"))
      }
      if (this.hasLabelTarget) this._after(tail, () => { this.labelTarget.textContent = "스크리닝 결과" })
    })
  }

  // 재실행 제출 → 기존 결과(카드+요약 칩)를 페이드아웃(서버 왕복 중 스포일러 제거). submit-loading 스피너와 병행.
  onRerun() {
    if (this._reduced) return
    const fade = (el) => { if (el) { el.style.transition = "opacity .2s ease"; el.style.opacity = "0" } }
    this.findingTargets.forEach(fade)
    if (this.hasSummaryTarget) fade(this.summaryTarget)
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
