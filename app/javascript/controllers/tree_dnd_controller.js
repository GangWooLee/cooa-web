import { Controller } from "@hotwired/stimulus"
import { csrfToken } from "controllers/lib/dom"
import { showNetErrorToast } from "controllers/lib/net_error_toast"

// 트리 드래그앤드롭 이동 — 폴더 위 가운데=안으로(자식), 행 사이 상/하=형제 정렬. 자기/자손은 거부.
// 재배치 후 깊이·들여쓰기가 바뀌므로 서버 렌더 트리를 다시 가져온다(Turbo.visit / reload).
export default class extends Controller {
  static targets = ["row"]

  dragstart(e) {
    const row = e.currentTarget
    this.dragId = row.dataset.nodeId
    this.dragDepth = parseInt(row.dataset.depth, 10)
    this.descendantIds = this._descendantIds(row)
    if (e.dataTransfer) { // 합성 이벤트(시스템 테스트)는 dataTransfer가 없을 수 있음 — 가드
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", this.dragId)
    }
  }

  // 평면 pre-order: 드래그 행 다음부터 depth > dragDepth 연속 행 = 자손
  _descendantIds(row) {
    const ids = new Set()
    let n = row.nextElementSibling
    while (n && parseInt(n.dataset.depth, 10) > this.dragDepth) {
      ids.add(n.dataset.nodeId)
      n = n.nextElementSibling
    }
    return ids
  }

  dragover(e) {
    if (!this.dragId) return
    const target = e.currentTarget
    const tid = target.dataset.nodeId
    if (tid === this.dragId || this.descendantIds.has(tid)) { // 자기/자손 거부
      if (e.dataTransfer) e.dataTransfer.dropEffect = "none"
      this._clear()
      this.intent = this.targetRow = null // 스테일 타겟으로 오드롭 방지
      return
    }
    e.preventDefault()
    if (e.dataTransfer) e.dataTransfer.dropEffect = "move"
    const rect = target.getBoundingClientRect()
    const y = (e.clientY - rect.top) / rect.height
    const intent = (target.dataset.kind === "folder" && y > 0.25 && y < 0.75)
      ? "inside" : (y < 0.5 ? "before" : "after")
    this._clear()
    target.classList.add(intent === "inside" ? "drop-inside" : (intent === "before" ? "drop-before" : "drop-after"))
    this.intent = intent
    this.targetRow = target
  }

  dragleave(e) {
    if (e.currentTarget.contains(e.relatedTarget)) return // 자식(라벨 등)로 이동 시 무시
    e.currentTarget.classList.remove("drop-before", "drop-after", "drop-inside")
    if (e.currentTarget === this.targetRow) this.intent = this.targetRow = null // 떠난 행이 캐시 타겟이면 해제
  }

  drop(e) {
    e.preventDefault()
    this._clear()
    if (!this.targetRow || !this.intent) return
    const tid = this.targetRow.dataset.nodeId
    const pid = this.targetRow.dataset.parentId || ""
    let body
    if (this.intent === "inside") body = { parent_id: tid }
    else if (this.intent === "before") body = { parent_id: pid, before_id: tid }
    else body = { parent_id: pid, after_id: tid }
    this._move(this.dragId, body)
  }

  dragend() { this._clear() }

  _clear() {
    this.rowTargets.forEach((r) => r.classList.remove("drop-before", "drop-after", "drop-inside"))
  }

  _move(id, body) {
    fetch(`/products/${id}/move`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken() },
      body: JSON.stringify(body)
    }).then(() => this._resync()).catch(() => { showNetErrorToast(); this._resync() }) // 네트워크 실패=무음 reload 직전 안내(E5)
  }

  // 성공=깊이/들여쓰기 재렌더, 거부(422)=서버 트리로 재동기 — 어느 쪽이든 서버 상태로 정합
  _resync() {
    if (window.Turbo) window.Turbo.visit(window.location.href, { action: "replace" })
    else window.location.reload()
  }
}
