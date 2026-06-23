import { Controller } from "@hotwired/stimulus"

// 재사용 아트워크 뷰어 — 줌/팬 · 바운딩박스 오버레이 · 미니맵 · 번호 포커스 · (옵션)드래그 생성
// 박스 클릭/번호 클릭 시 "artwork-viewer:focus" 이벤트(detail:{seq}) 디스패치 → 페이지가 상세 패널 전환.
// Shift+드래그(drawable) → "artwork-viewer:draw" 이벤트(detail:{x,y,w,h} %) 디스패치 → 페이지가 코멘트 작성.
export default class extends Controller {
  static targets = ["stage", "image", "minimap", "viewport", "box", "draftBox"]
  static values = { drawable: { type: Boolean, default: false }, maxScale: { type: Number, default: 6 } }

  connect() {
    this.scale = 1; this.tx = 0; this.ty = 0; this.fitScale = 1
    this.nat = { w: 0, h: 0 }
    this._resize = () => this.fit()
    window.addEventListener("resize", this._resize)
    this.element.addEventListener("pointerdown", this.onDown)
    this.element.addEventListener("wheel", this.onWheel, { passive: false })
    const img = this.imageTarget
    if (img.complete && img.naturalWidth) this.ready()
    else img.addEventListener("load", () => this.ready(), { once: true })
  }

  disconnect() {
    window.removeEventListener("resize", this._resize)
    this.element.removeEventListener("pointerdown", this.onDown)
    this.element.removeEventListener("wheel", this.onWheel)
  }

  ready() {
    this.nat = { w: this.imageTarget.naturalWidth, h: this.imageTarget.naturalHeight }
    this.fit()
  }

  get rect() { return this.element.getBoundingClientRect() }

  fit() {
    if (!this.nat.w) return
    const c = this.rect
    this.fitScale = Math.min(c.width / this.nat.w, c.height / this.nat.h) || 1
    this.scale = this.fitScale
    this.tx = (c.width - this.nat.w * this.scale) / 2
    this.ty = (c.height - this.nat.h * this.scale) / 2
    this.highlight(null)
    this.apply()
  }

  apply() {
    this.stageTarget.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`
    this.updateMinimap()
  }

  clampScale(s) {
    return Math.min(Math.max(s, this.fitScale * 0.85), this.fitScale * this.maxScaleValue)
  }

  // ── 줌 ──
  onWheel = (e) => {
    e.preventDefault()
    const c = this.rect
    this.zoomAt(e.clientX - c.left, e.clientY - c.top, e.deltaY < 0 ? 1.12 : 1 / 1.12)
  }
  zoomAt(cx, cy, factor) {
    const ns = this.clampScale(this.scale * factor)
    const ix = (cx - this.tx) / this.scale, iy = (cy - this.ty) / this.scale
    this.scale = ns; this.tx = cx - ix * ns; this.ty = cy - iy * ns
    this.apply()
  }
  zoomIn() { const c = this.rect; this.zoomAt(c.width / 2, c.height / 2, 1.3) }
  zoomOut() { const c = this.rect; this.zoomAt(c.width / 2, c.height / 2, 1 / 1.3) }

  // ── 팬 / 드로잉 ──
  onDown = (e) => {
    if (e.target.closest(".av-ui, [data-artwork-viewer-target='box']")) return
    if (this.drawableValue && e.shiftKey) return this.startDraw(e)
    e.preventDefault()
    const sx = e.clientX, sy = e.clientY, tx0 = this.tx, ty0 = this.ty
    const move = (ev) => { this.tx = tx0 + (ev.clientX - sx); this.ty = ty0 + (ev.clientY - sy); this.apply() }
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up) }
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up)
  }

  startDraw(e) {
    e.preventDefault()
    const c = this.rect
    const toImg = (clientX, clientY) => ({
      x: (clientX - c.left - this.tx) / this.scale / this.nat.w * 100,
      y: (clientY - c.top - this.ty) / this.scale / this.nat.h * 100
    })
    const start = toImg(e.clientX, e.clientY)
    const draft = this.draftBoxTarget
    draft.classList.remove("hidden")
    const draw = (ev) => {
      const p = toImg(ev.clientX, ev.clientY)
      const x = Math.min(start.x, p.x), y = Math.min(start.y, p.y)
      const w = Math.abs(p.x - start.x), h = Math.abs(p.y - start.y)
      Object.assign(draft.style, { left: x + "%", top: y + "%", width: w + "%", height: h + "%" })
      draft.dataset.box = JSON.stringify({ x, y, w, h })
    }
    const up = () => {
      window.removeEventListener("pointermove", draw); window.removeEventListener("pointerup", up)
      const box = JSON.parse(draft.dataset.box || "{}")
      draft.classList.add("hidden")
      if (box.w > 1.5 && box.h > 1) this.dispatch("draw", { detail: box })
    }
    window.addEventListener("pointermove", draw); window.addEventListener("pointerup", up)
  }

  // ── 포커스 ──
  focusBox(e) { this.focus(e.currentTarget.dataset.seq) }
  focusSeq(e) { this.focus(e.currentTarget.dataset.seq) }

  focus(seq) {
    const el = this.boxTargets.find((b) => b.dataset.seq == seq)
    if (!el) return
    const bx = +el.dataset.x, by = +el.dataset.y, bw = +el.dataset.w, bh = +el.dataset.h
    const pxw = bw / 100 * this.nat.w, pxh = bh / 100 * this.nat.h
    const cx = (bx + bw / 2) / 100 * this.nat.w, cy = (by + bh / 2) / 100 * this.nat.h
    const c = this.rect, pad = 0.5
    this.scale = this.clampScale(Math.min(c.width * pad / pxw, c.height * pad / pxh))
    this.tx = c.width / 2 - cx * this.scale
    this.ty = c.height / 2 - cy * this.scale
    this.stageTarget.style.transition = "transform .35s ease"
    this.apply()
    setTimeout(() => (this.stageTarget.style.transition = ""), 380)
    this.highlight(seq)
    this.dispatch("focus", { detail: { seq } })
  }

  highlight(seq) {
    this.boxTargets.forEach((b) => {
      const on = b.dataset.seq == seq
      b.style.boxShadow = on ? "0 0 0 3px rgba(0,0,0,.18)" : "none"
      b.style.zIndex = on ? "5" : "1"
    })
    this.element.querySelectorAll(".av-seq").forEach((btn) => {
      const on = btn.dataset.seq == seq
      btn.style.background = on ? btn.style.borderColor : "transparent"
      btn.style.color = on ? "#fff" : btn.style.borderColor
    })
  }

  // ── 미니맵 ──
  updateMinimap() {
    if (!this.hasViewportTarget || !this.nat.w) return
    const mm = this.minimapTarget.getBoundingClientRect()
    const c = this.rect
    const rx = mm.width / this.nat.w, ry = mm.height / this.nat.h
    const vx = -this.tx / this.scale, vy = -this.ty / this.scale
    const vw = c.width / this.scale, vh = c.height / this.scale
    const vp = this.viewportTarget
    vp.style.left = Math.max(0, vx * rx) + "px"
    vp.style.top = Math.max(0, vy * ry) + "px"
    vp.style.width = Math.min(mm.width, vw * rx) + "px"
    vp.style.height = Math.min(mm.height, vh * ry) + "px"
  }

  minimapClick(e) {
    const mm = this.minimapTarget.getBoundingClientRect()
    const px = (e.clientX - mm.left) / mm.width * this.nat.w
    const py = (e.clientY - mm.top) / mm.height * this.nat.h
    const c = this.rect
    this.tx = c.width / 2 - px * this.scale
    this.ty = c.height / 2 - py * this.scale
    this.apply()
  }
}
