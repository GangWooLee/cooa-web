import { Controller } from "@hotwired/stimulus"
import { bindDismiss, unbindDismiss } from "controllers/lib/dismissable"
import { submitDynamicForm } from "controllers/lib/dom"

// 트리 우클릭 컨텍스트 메뉴 — 경로 복사 / 이름 변경 / 삭제 (사이드바·대시보드 공용)
export default class extends Controller {
  static targets = ["menu", "toast"]
  static values = { renameParam: { type: String, default: "rename_side" } } // 사이드바=rename_side / 대시보드=rename

  connect() { bindDismiss(this, { contains: (t) => this.menuTarget.contains(t), onScroll: true }) }
  disconnect() { unbindDismiss(this) }

  open(e) {
    e.preventDefault()
    const el = e.currentTarget
    this.node = {
      id: el.dataset.nodeId, kind: el.dataset.nodeKind, name: el.dataset.nodeName,
      path: el.dataset.nodePath, confirm: el.dataset.nodeConfirm
    }
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
    const url = `/?${this.renameParamValue}=${id}` // 행동한 트리에서 인라인 명명(사이드바=rename_side / 대시보드=rename)
    if (window.Turbo) window.Turbo.visit(url); else window.location.assign(url)
  }

  del() {
    const n = this.node
    this.hide()
    if (!window.confirm(n.confirm)) return
    submitDynamicForm(`/products/${n.id}`, { _method: "delete" }) // 삭제 메시지는 data-node-confirm(서버 helper) 단일 출처
  }
}
