import { Controller } from "@hotwired/stimulus"
import { submitDynamicForm } from "controllers/lib/dom"

// 트리 선택 + 상단 아이콘 생성 — _list 루트에 부착.
// 행 클릭 시 선택 표시(토글/드로어와 공존), 상단 폴더/파일 아이콘은 선택 노드 기준(relative_to)으로 생성.
export default class extends Controller {
  static values = { createUrl: String, workspaceId: Number }

  select(e) {
    const tr = e.currentTarget
    if (!tr?.dataset.nodeId) return
    this.selectedId = tr.dataset.nodeId
    this.element.querySelectorAll("tr.tree-selected").forEach((r) => r.classList.remove("tree-selected"))
    tr.classList.add("tree-selected")
  }

  newFolder(e) { this._create("folder", e) }
  newItem(e) { this._create("item", e) }

  // 선택 노드 기준으로 생성(서버 apply_creation_context가 parent_id·position 결정) → 트리 인라인 명명.
  // 현재 작업실 id를 실어 보낸다(D3): 미선택 = 루트 생성이면 이 작업실에 귀속(빈 작업실도 첫 항목이 여기로),
  // 폴더 선택 = 자식 생성이면 서버가 workspace_id를 무시(brand_root로 도출) — 항상 실어도 무해.
  _create(kind, e) {
    this._markLoading(e?.currentTarget) // 클릭 즉시 피드백 — 별도 폼 네비라 버튼 disable은 제출에 무간섭
    const fields = { "product[kind]": kind, relative_to: this.selectedId }
    if (this.hasWorkspaceIdValue && this.workspaceIdValue) fields.workspace_id = this.workspaceIdValue
    submitDynamicForm(this.createUrlValue, fields)
  }

  // 아이콘→스피너 교체 + disable(라벨 유지). 풀 네비가 페이지를 교체하므로 리셋 불요.
  _markLoading(btn) {
    if (!btn) return
    btn.disabled = true
    btn.classList.add("opacity-70")
    btn.querySelector("svg")?.replaceWith(Object.assign(document.createElement("span"), {
      className: "spinner", ariaHidden: "true"
    }))
  }
}
