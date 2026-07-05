import { Controller } from "@hotwired/stimulus"
import { bindDismiss, unbindDismiss } from "controllers/lib/dismissable"
import { submitDynamicForm } from "controllers/lib/dom"

// 홈 작업실 카드 우클릭 컨텍스트 메뉴(D3) — 이름 변경(prompt→PATCH) / 삭제(confirm→DELETE). tree-ctx의
// 작업실판(대상이 제품이 아니라 workspaces#update/destroy라 별도). 관리 권한자(@can_manage_workspaces)일 때만 렌더.
export default class extends Controller {
  static targets = ["menu"]

  connect() { bindDismiss(this, { contains: (t) => this.menuTarget.contains(t), onScroll: true }) }
  disconnect() { unbindDismiss(this) }

  open(e) {
    e.preventDefault()
    const el = e.currentTarget
    this.ws = { id: el.dataset.workspaceId, name: el.dataset.workspaceName }
    const m = this.menuTarget
    m.classList.remove("hidden")
    const mw = m.offsetWidth || 176, mh = m.offsetHeight || 96 // 뷰포트 경계 보정
    m.style.left = `${Math.min(e.clientX, window.innerWidth - mw - 8)}px`
    m.style.top = `${Math.min(e.clientY, window.innerHeight - mh - 8)}px`
  }

  hide() { this.menuTarget.classList.add("hidden") }

  rename() {
    const ws = this.ws
    this.hide()
    const name = window.prompt("새 작업실 이름", ws.name)
    if (name === null) return
    const trimmed = name.trim()
    if (!trimmed || trimmed === ws.name) return
    submitDynamicForm(`/workspaces/${ws.id}`, { _method: "patch", name: trimmed })
  }

  del() {
    const ws = this.ws
    this.hide()
    if (!window.confirm(`'${ws.name}' 작업실을 삭제할까요? (제품이 남아 있으면 삭제되지 않습니다)`)) return
    submitDynamicForm(`/workspaces/${ws.id}`, { _method: "delete" })
  }
}
