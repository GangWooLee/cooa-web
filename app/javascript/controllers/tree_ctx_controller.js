import { Controller } from "@hotwired/stimulus"

// 사이드바 트리 우클릭 컨텍스트 메뉴 — 경로 복사 / 이름 변경 / 삭제
export default class extends Controller {
  static targets = ["menu", "toast"]

  connect() {
    this._close = (e) => { if (!this.menuTarget.contains(e.target)) this.hide() }
    this._esc = (e) => { if (e.key === "Escape") this.hide() }
    this._scroll = () => this.hide()
    document.addEventListener("click", this._close)
    document.addEventListener("keydown", this._esc)
    document.addEventListener("scroll", this._scroll, true)
  }

  disconnect() {
    document.removeEventListener("click", this._close)
    document.removeEventListener("keydown", this._esc)
    document.removeEventListener("scroll", this._scroll, true)
  }

  open(e) {
    e.preventDefault()
    const el = e.currentTarget
    this.node = { id: el.dataset.nodeId, kind: el.dataset.nodeKind, name: el.dataset.nodeName, path: el.dataset.nodePath }
    if (this.hasToastTarget) this.toastTarget.classList.add("hidden")
    const m = this.menuTarget
    m.classList.remove("hidden")
    const mw = m.offsetWidth || 176, mh = m.offsetHeight || 130 // 뷰포트 경계 보정
    m.style.left = `${Math.min(e.clientX, window.innerWidth - mw - 8)}px`
    m.style.top = `${Math.min(e.clientY, window.innerHeight - mh - 8)}px`
  }

  hide() { this.menuTarget.classList.add("hidden") }

  async copyPath() {
    try { await navigator.clipboard.writeText(this.node?.path || "") } catch (_) { /* 권한/비보안 컨텍스트 */ }
    if (this.hasToastTarget) { this.toastTarget.classList.remove("hidden"); setTimeout(() => this.hide(), 800) }
    else this.hide()
  }

  rename() {
    const id = this.node?.id
    this.hide()
    const url = `/?rename=${id}` // 대시보드 트리에서 인라인 명명(기존 흐름 재사용)
    if (window.Turbo) window.Turbo.visit(url); else window.location.assign(url)
  }

  del() {
    const n = this.node
    this.hide()
    const msg = n.kind === "folder"
      ? `'${n.name}' 및 모든 하위 항목·구성요소·버전이 영구 삭제됩니다. 계속할까요?`
      : `'${n.name}' 및 모든 구성요소·버전이 삭제됩니다. 계속할까요?`
    if (!window.confirm(msg)) return
    const form = document.createElement("form")
    form.method = "post"
    form.action = `/products/${n.id}`
    form.dataset.turboFrame = "_top"
    this._hidden(form, "_method", "delete")
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) this._hidden(form, "authenticity_token", token)
    document.body.appendChild(form)
    form.requestSubmit()
  }

  _hidden(form, name, value) {
    const i = document.createElement("input")
    i.type = "hidden"; i.name = name; i.value = value
    form.appendChild(i)
  }
}
