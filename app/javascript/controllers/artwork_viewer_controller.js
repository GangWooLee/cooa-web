import { Controller } from "@hotwired/stimulus"

// 재사용 아트워크 뷰어 (단일/듀얼 pane).
//  · 하나의 transform(tx,ty,scale)을 모든 stage에 동시 적용 → 듀얼이 자연 동기화.
//  · 박스/번호 클릭 focus(seq): 양쪽 동시 확대 + 비선택 박스 흐림(opacity↓). "artwork-viewer:focus" 디스패치.
//  · autofocus: 첫 박스로 시작. fit: 전체 보기(선택·흐림 해제).
//  · drawable: 마지막 pane(현재)에서 Shift+드래그 → "artwork-viewer:draw"(%좌표) 디스패치.
export default class extends Controller {
  static targets = ["canvas", "pane", "stage", "image", "minimap", "viewport", "box", "draftBox", "hint"]
  static values = {
    drawable: { type: Boolean, default: false },
    autofocus: { type: Boolean, default: false },
    maxScale: { type: Number, default: 6 }
  }

  connect() {
    this.scale = 1; this.tx = 0; this.ty = 0; this.fitScale = 1
    this.nat = { w: 0, h: 0 }; this.activeSeq = null
    this._resize = () => this.refit()
    window.addEventListener("resize", this._resize)
    this.surface = this.hasCanvasTarget ? this.canvasTarget : this.element
    this.surface.addEventListener("pointerdown", this.onDown)
    this.surface.addEventListener("wheel", this.onWheel, { passive: false })
    const img = this.imageTargets[0]
    if (img && img.complete && img.naturalWidth) this.ready()
    else if (img) img.addEventListener("load", () => this.ready(), { once: true })
  }

  disconnect() {
    window.removeEventListener("resize", this._resize)
    this.surface.removeEventListener("pointerdown", this.onDown)
    this.surface.removeEventListener("wheel", this.onWheel)
  }

  ready() {
    const img = this.imageTargets[0]
    this.nat = { w: img.naturalWidth, h: img.naturalHeight }
    this.fit()
    if (this.autofocusValue) {
      const first = this.firstSeq()
      if (first != null) this.focus(first)
    }
    if (this.hasHintTarget) {
      setTimeout(() => { if (this.hasHintTarget) this.hintTarget.style.opacity = "0" }, 2500)
      setTimeout(() => { if (this.hasHintTarget) this.hintTarget.style.display = "none" }, 3050)
    }
  }

  // resize 시 현재가 포커스 상태면 유지, 아니면 fit
  refit() {
    if (this.activeSeq != null) this.focus(this.activeSeq, false)
    else this.fit()
  }

  firstSeq() {
    const seqs = this.boxTargets.map((b) => +b.dataset.seq)
    return seqs.length ? Math.min(...seqs) : null
  }

  // 기준 pane(panes 동일 크기 → 첫 pane), 좌표 계산용
  get rect() { return this.paneTargets[0].getBoundingClientRect() }
  paneAt(x, y) {
    return this.paneTargets.find((p) => {
      const r = p.getBoundingClientRect()
      return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom
    }) || this.paneTargets[0]
  }

  fit() {
    if (!this.nat.w) return
    const c = this.rect
    this.fitScale = Math.min(c.width / this.nat.w, c.height / this.nat.h) || 1
    this.scale = this.fitScale
    this.tx = (c.width - this.nat.w * this.scale) / 2
    this.ty = (c.height - this.nat.h * this.scale) / 2
    this.activeSeq = null
    this.highlight(null)
    this.apply()
  }

  apply() {
    const t = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`
    this.stageTargets.forEach((s) => (s.style.transform = t))
    this.updateMinimap()
  }

  clampScale(s) { return Math.min(Math.max(s, this.fitScale * 0.85), this.fitScale * this.maxScaleValue) }

  // ── 줌 ──
  onWheel = (e) => {
    if (e.target.closest(".av-ui")) return
    e.preventDefault()
    const r = this.paneAt(e.clientX, e.clientY).getBoundingClientRect()
    this.zoomAt(e.clientX - r.left, e.clientY - r.top, e.deltaY < 0 ? 1.12 : 1 / 1.12)
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
    const lastPane = this.paneTargets[this.paneTargets.length - 1]
    if (this.drawableValue && e.shiftKey && this.paneAt(e.clientX, e.clientY) === lastPane) return this.startDraw(e)
    e.preventDefault()
    const sx = e.clientX, sy = e.clientY, tx0 = this.tx, ty0 = this.ty
    const move = (ev) => { this.tx = tx0 + (ev.clientX - sx); this.ty = ty0 + (ev.clientY - sy); this.apply() }
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up) }
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up)
  }

  startDraw(e) {
    e.preventDefault()
    const last = this.paneTargets.length - 1
    const r = this.paneTargets[last].getBoundingClientRect()
    const draft = this.draftBoxTargets[this.draftBoxTargets.length - 1]
    if (!draft) return
    const toImg = (x, y) => ({
      x: (x - r.left - this.tx) / this.scale / this.nat.w * 100,
      y: (y - r.top - this.ty) / this.scale / this.nat.h * 100
    })
    const start = toImg(e.clientX, e.clientY)
    draft.classList.remove("hidden")
    const draw = (ev) => {
      const q = toImg(ev.clientX, ev.clientY)
      const x = Math.min(start.x, q.x), y = Math.min(start.y, q.y)
      const w = Math.abs(q.x - start.x), h = Math.abs(q.y - start.y)
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

  focus(seq, animate = true) {
    const el = this.boxTargets.find((b) => b.dataset.seq == seq)
    if (!el) return
    const bx = +el.dataset.x, by = +el.dataset.y, bw = +el.dataset.w, bh = +el.dataset.h
    const pxw = bw / 100 * this.nat.w, pxh = bh / 100 * this.nat.h
    const cx = (bx + bw / 2) / 100 * this.nat.w, cy = (by + bh / 2) / 100 * this.nat.h
    const c = this.rect, pad = 0.5
    this.scale = this.clampScale(Math.min(c.width * pad / pxw, c.height * pad / pxh))
    this.tx = c.width / 2 - cx * this.scale
    this.ty = c.height / 2 - cy * this.scale
    this.activeSeq = seq
    if (animate) {
      this.stageTargets.forEach((s) => (s.style.transition = "transform .35s ease"))
      this.apply()
      setTimeout(() => this.stageTargets.forEach((s) => (s.style.transition = "")), 380)
    } else {
      this.apply()
    }
    this.highlight(seq)
    this.dispatch("focus", { detail: { seq } })
  }

  // 선택 박스 강조 + 비선택 박스 흐림(모든 pane)
  highlight(seq) {
    this.boxTargets.forEach((b) => {
      const on = seq != null && b.dataset.seq == seq
      const dim = seq != null && !on
      b.style.opacity = dim ? "0.16" : "1"
      b.style.boxShadow = on ? "0 0 0 3px rgba(0,0,0,.2)" : "none"
      b.style.zIndex = on ? "5" : "1"
    })
    this.element.querySelectorAll(".av-seq").forEach((btn) => {
      const on = btn.dataset.seq == seq
      btn.style.background = on ? btn.style.borderColor : "transparent"
      btn.style.color = on ? "#fff" : btn.style.borderColor
    })
    this.element.querySelectorAll(".av-thumb").forEach((t) => {
      const on = t.dataset.seq == seq
      t.style.outline = on ? "2px solid #111827" : "none"
      t.style.outlineOffset = "1px"
      t.style.opacity = seq != null && !on ? "0.5" : "1"
    })
  }

  // ── 미니맵 (1개) ──
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
    this.activeSeq = null
    this.highlight(null)
    this.apply()
  }
}
