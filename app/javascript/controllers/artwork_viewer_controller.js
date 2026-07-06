import { Controller } from "@hotwired/stimulus"

// 재사용 아트워크 뷰어 (단일/듀얼 pane).
//  · 하나의 transform(tx,ty,scale)을 모든 stage에 동시 적용 → 듀얼이 자연 동기화.
//  · 박스/번호 클릭 focus(seq): 양쪽 동시 확대 + 비선택 박스 흐림(opacity↓). "artwork-viewer:focus" 디스패치.
//  · autofocus: 첫 박스로 시작. fit: 전체 보기(선택·흐림 해제).
//  · drawable: 마지막 pane(현재)에서 Shift+드래그 → "artwork-viewer:draw"(%좌표) 디스패치.
export default class extends Controller {
  static targets = ["canvas", "pane", "stage", "image", "page", "minimap", "viewport", "box", "draftBox", "hint", "notice", "drawToggle"]
  static values = {
    drawable: { type: Boolean, default: false },
    autofocus: { type: Boolean, default: false },
    maxScale: { type: Number, default: 6 },
    workerSrc: { type: String, default: "" } // PDF.js worker(asset_path). 이미지 pane엔 빈 문자열.
  }

  connect() {
    this.scale = 1; this.tx = 0; this.ty = 0; this.fitScale = 1
    this.drawMode = false // "영역 표시" 토글(버튼) — on이면 드래그=박스 드로우(Shift 불요). Shift+드래그는 상시 병행.
    this.nat = { w: 0, h: 0 }; this.activeSeq = null
    this._resize = () => this.refit()
    window.addEventListener("resize", this._resize)
    this.surface = this.hasCanvasTarget ? this.canvasTarget : this.element
    this.surface.addEventListener("pointerdown", this.onDown)
    this.surface.addEventListener("wheel", this.onWheel, { passive: false })
    this._pdfEntries = [] // {canvas, page, vp1, task}
    this.initSurfaces().catch((e) => console.error("뷰어 초기화 실패", e)) // 마지막 안전망(무음 사망 방지)
  }

  disconnect() {
    this._endGesture?.() // 진행 중 pan/draw의 window pointermove/up 정리(좀비 리스너·GC 차단 방지)
    clearTimeout(this._rerenderT)
    clearTimeout(this._noticeT)
    this._pdfEntries?.forEach((e) => { try { e.task?.cancel() } catch (err) { /* noop */ } })
    window.removeEventListener("resize", this._resize)
    this.surface.removeEventListener("pointerdown", this.onDown)
    this.surface.removeEventListener("wheel", this.onWheel)
  }

  // 표면 초기화: nat(자연 치수)의 단일 의존점. 이미지 pane은 <img>.naturalWidth, PDF pane은 PDF.js
  // 페이지 뷰포트에서 취득. nat만 올바르면 fit/줌/박스/미니맵은 표면 무관하게 그대로 동작한다.
  // PDF 실패는 pane 단위로 격리(sticky notice) — 혼합 비교에서 멀쩡한 이미지 pane까지 죽이지 않는다.
  async initSurfaces() {
    if (this.paneTargets.some((p) => p.querySelector("[data-artwork-viewer-target='page']"))) {
      try {
        await this.loadPdfPanes() // pane0가 PDF면 this.nat 설정 + 모든 PDF pane 로드
      } catch (e) {
        console.error("PDF 로드 단계 실패", e)
        this.showNotice("PDF 뷰어를 불러오지 못했습니다 — 새로고침 후에도 반복되면 파일을 확인하세요.", { sticky: true })
      }
    }
    const pane0 = this.paneTargets[0]
    const canvas0 = pane0?.querySelector("[data-artwork-viewer-target='page']")
    const img0 = pane0?.querySelector("[data-artwork-viewer-target='image']")
    if (canvas0) {
      // pane0 PDF 실패여도 다른 pane이 로드됐으면 그 치수로 뷰어를 살린다(형제 pane까지 데드 방지).
      if (!this.nat.w && this._pdfEntries.length) {
        const vp1 = this._pdfEntries[0].vp1
        this.nat = { w: vp1.width, h: vp1.height }
      }
      if (this.nat.w) { this.ready(); this.renderPdfPanes() }
    } else if (img0) {
      const go = () => { this.nat = { w: img0.naturalWidth, h: img0.naturalHeight }; this.ready(); this.renderPdfPanes() }
      if (img0.complete && img0.naturalWidth) go()
      else img0.addEventListener("load", go, { once: true })
    }
    // 비교뷰: pane0 외 이미지가 늦게 로드되면 naturalWidth가 뒤늦게 확정 → 정규화 계수 재적용
    this.imageTargets.slice(1).forEach((im) => {
      if (!(im.complete && im.naturalWidth)) im.addEventListener("load", () => this.apply(), { once: true })
    })
  }

  // PDF pane 로드 — 문서 fetch+파스는 병렬(2-PDF 비교뷰 최초 표시 지연 반감), nat은 pane0에서.
  // 모듈/문서 실패는 던지지 않고 sticky notice로 사용자에게 알린다(빈 화면 무음 금지).
  async loadPdfPanes() {
    let pdfjs
    try {
      pdfjs = await import("pdfjs-dist")
      if (this.workerSrcValue) pdfjs.GlobalWorkerOptions.workerSrc = this.workerSrcValue
    } catch (e) {
      console.error("PDF.js 모듈 로드 실패", e)
      this.showNotice("PDF 뷰어 모듈을 불러오지 못했습니다 — 네트워크 상태를 확인하고 새로고침하세요.", { sticky: true })
      return
    }
    const loads = this.paneTargets.map((pane, i) => {
      const canvas = pane.querySelector("[data-artwork-viewer-target='page']")
      if (!canvas) return null
      return pdfjs.getDocument({ url: canvas.dataset.pdfSrc, isEvalSupported: false }).promise
        .then(async (doc) => ({ i, canvas, page: await doc.getPage(1), numPages: doc.numPages })) // v1: 첫 페이지만
        .catch((e) => { console.error("PDF 로드 실패", e); return { i, canvas, error: e } })
    }).filter(Boolean)
    let failed = 0
    for (const s of await Promise.all(loads)) {
      if (s.error) { failed += 1; continue }
      const vp1 = s.page.getViewport({ scale: 1 })
      if (s.i === 0) this.nat = { w: vp1.width, h: vp1.height }
      // 안전 경고는 상시 유지(sticky) — 검토자가 6초 뒤 합류해도 "1/N만 보고 있다"를 항상 인지(F8/EC-4)
      if (s.numPages > 1) this.showNotice(`이 PDF는 ${s.numPages}페이지 — 현재 1페이지만 표시 중`, { sticky: true })
      this._pdfEntries.push({ canvas: s.canvas, page: s.page, vp1, task: null })
    }
    if (failed > 0) {
      this.showNotice("PDF를 표시할 수 없습니다 — 파일이 손상되었거나 암호로 보호되어 있을 수 있습니다.", { sticky: true })
    }
  }

  renderPdfPanes() {
    if (!this._pdfEntries.length) return
    this._lastRenderScale = this.scale
    this._pdfEntries.forEach((e) => this.renderPdfEntry(e, this.scale))
  }

  // 오프스크린에 (표시배율 × dpr)로 래스터화 후 한 번에 blit — 재렌더 중 기존 화면 유지(blank 플래시
  // 제거, F9/PERF-3). backing store는 면적 상한(32MP)으로 OOM 방지(단일축 8192보다 엄밀, EC-8).
  async renderPdfEntry(entry, cssScale) {
    const { canvas, page, vp1 } = entry
    const dpr = window.devicePixelRatio || 1
    const areaCap = Math.sqrt(32_000_000 / (vp1.width * vp1.height)) // w×h ≤ 32MP
    // 실제 표시 배율 = scale × pane 정규화 계수(k) — 이종 치수 비교에서 k>1인 pane도 물리픽셀 선명도 유지
    const pane = canvas.closest("[data-artwork-viewer-target='pane']")
    const k = pane ? this.paneScaleFactor(pane) : 1
    const renderScale = Math.min(Math.max(cssScale * k, 0.1) * dpr, areaCap)
    const vp = page.getViewport({ scale: renderScale })
    if (entry.task) { try { entry.task.cancel() } catch (e) { /* noop */ } } // 동일 문서 다중 render 금지
    const off = document.createElement("canvas")
    off.width = Math.floor(vp.width)
    off.height = Math.floor(vp.height)
    entry.task = page.render({ canvasContext: off.getContext("2d"), viewport: vp })
    try {
      await entry.task.promise
      canvas.width = off.width
      canvas.height = off.height
      canvas.style.width = Math.floor(vp1.width) + "px"
      canvas.style.height = Math.floor(vp1.height) + "px"
      canvas.getContext("2d").drawImage(off, 0, 0)
      canvas.dataset.rendered = "1"
    } catch (e) { /* cancelled — 기존 화면 유지 */ }
  }

  // 줌 종료 시(디바운스) 현재 배율로 재렌더 — 팬(scale 불변)은 가드로 스킵.
  scheduleRerender() {
    if (!this._pdfEntries || !this._pdfEntries.length) return
    clearTimeout(this._rerenderT)
    this._rerenderT = setTimeout(() => {
      const last = this._lastRenderScale || 1
      if (Math.abs(this.scale - last) / last < 0.02) return
      this._lastRenderScale = this.scale
      this._pdfEntries.forEach((e) => this.renderPdfEntry(e, this.scale))
    }, 180)
  }

  // sticky: 에러류는 자동 숨김 없이 유지(사용자가 원인 인지 후 조치하도록). 정보류는 6초 후 숨김.
  showNotice(text, { sticky = false } = {}) {
    if (!this.hasNoticeTarget) return
    this.noticeTarget.textContent = text
    this.noticeTarget.classList.remove("hidden")
    clearTimeout(this._noticeT)
    if (!sticky) this._noticeT = setTimeout(() => { if (this.hasNoticeTarget) this.noticeTarget.classList.add("hidden") }, 6000)
  }

  ready() {
    if (!this.nat.w) return
    this.correctThumbAspects() // 필름스트립 크롭 비율을 실제 아트워크 치수로 교정(IMG_RATIO 하드코드 탈피)
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
    if (this.activeSeq != null) this.zoomToBox(this.activeSeq, false)
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

  // pane 콘텐츠의 자연 폭(px) — PDF는 로드된 페이지 vp1, 이미지는 naturalWidth. 미로드/실패면 0.
  paneNatW(pane) {
    const canvas = pane.querySelector("[data-artwork-viewer-target='page']")
    if (canvas) {
      const entry = this._pdfEntries.find((e) => e.canvas === canvas)
      return entry ? entry.vp1.width : 0
    }
    const img = pane.querySelector("[data-artwork-viewer-target='image']")
    return img ? img.naturalWidth : 0
  }

  // pane별 정규화 계수 k = nat.w / 자기 자연폭. 이종 치수 비교(구버전 이미지 2048px vs 신버전 PDF
  // 1024pt)에서 모든 pane이 같은 표시 폭(nat.w×scale)으로 정렬되어 (1) 우측 pane 배율 왜곡과
  // (2) draw %-환산 오염(toImg는 nat 기준 — 표시폭이 nat×scale일 때만 정확)이 함께 해소된다(F2).
  paneScaleFactor(pane) {
    const w = this.paneNatW(pane)
    return w > 0 && this.nat.w > 0 ? this.nat.w / w : 1
  }

  apply() {
    this.stageTargets.forEach((s) => {
      const pane = s.closest("[data-artwork-viewer-target='pane']")
      const k = pane ? this.paneScaleFactor(pane) : 1
      s.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale * k})`
    })
    this.updateMinimap()
    this.scheduleRerender() // PDF면 줌 변화 시 재렌더(가드로 팬은 스킵)
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

  // "영역 표시" 토글: on이면 드래그로 박스 드로우(Shift 불요), off면 드래그=팬. 버튼 aria-pressed로 활성 표시.
  toggleDraw(e) {
    this.drawMode = !this.drawMode
    e.currentTarget.setAttribute("aria-pressed", this.drawMode ? "true" : "false")
  }

  // ── 팬 / 드로잉 ──
  onDown = (e) => {
    if (e.target.closest(".av-ui, [data-artwork-viewer-target='box']")) return
    const lastPane = this.paneTargets[this.paneTargets.length - 1]
    if (this.drawableValue && (e.shiftKey || this.drawMode) && this.paneAt(e.clientX, e.clientY) === lastPane) return this.startDraw(e)
    e.preventDefault()
    const sx = e.clientX, sy = e.clientY, tx0 = this.tx, ty0 = this.ty
    const move = (ev) => { this.tx = tx0 + (ev.clientX - sx); this.ty = ty0 + (ev.clientY - sy); this.apply() }
    const end = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", end); this._endGesture = null }
    this._endGesture = end // disconnect 시에도 정리되도록 보관
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", end)
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
    const cleanup = () => { window.removeEventListener("pointermove", draw); window.removeEventListener("pointerup", up); this._endGesture = null }
    const up = () => {
      cleanup()
      const box = JSON.parse(draft.dataset.box || "{}")
      draft.classList.add("hidden")
      if (box.w > 1.5 && box.h > 1) this.dispatch("draw", { detail: box })
    }
    this._endGesture = cleanup // disconnect 시 리스너만 정리(draw 디스패치 없이)
    window.addEventListener("pointermove", draw); window.addEventListener("pointerup", up)
  }

  // ── 포커스 ──
  focusBox(e) { this.focus(e.currentTarget.dataset.seq) }
  focusSeq(e) { this.focus(e.currentTarget.dataset.seq) }

  // 사용자 클릭: 같은 박스 재클릭이면 선택만 해제(흐림 제거·줌 유지), 아니면 그 박스로 확대
  focus(seq, animate = true) {
    if (this.activeSeq != null && String(this.activeSeq) === String(seq)) {
      this.activeSeq = null
      this.highlight(null) // 흐림 해제 — scale/tx/ty 유지(확대 안 되돌림)
      this.dispatch("focus", { detail: { seq: null } })
      return
    }
    this.zoomToBox(seq, animate)
  }

  // 박스로 확대(토글 없음) — refit/프로그램적 재포커스용
  zoomToBox(seq, animate = true) {
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

  // 필름스트립 썸네일의 aspect-ratio를 실제 아트워크 비율(nat)로 교정. 서버는 아트워크 치수를 모르는 채
  // 레거시 IMG_RATIO(2048:1118)로 근사 렌더하는데, 비율이 다른 PDF/이미지에선 크롭이 왜곡된다(F4).
  // crop_bg의 background-size 산식은 요소 비율이 (w%×W)/(h%×H)일 때만 무왜곡 — nat 확보 시점에 보정.
  correctThumbAspects() {
    this.element.querySelectorAll(".av-thumb[data-w]").forEach((t) => {
      const w = parseFloat(t.dataset.w), h = parseFloat(t.dataset.h)
      if (w > 0 && h > 0) t.style.aspectRatio = ((w * this.nat.w) / (h * this.nat.h)).toFixed(3)
    })
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
