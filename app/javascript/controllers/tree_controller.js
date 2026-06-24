import { Controller } from "@hotwired/stimulus"
import { submitDynamicForm } from "controllers/lib/dom"

// 트리 선택 + 상단 아이콘 생성 — _list 루트에 부착.
// 행 클릭 시 선택 표시(토글/드로어와 공존), 상단 폴더/파일 아이콘은 선택 노드 기준(relative_to)으로 생성.
export default class extends Controller {
  static values = { createUrl: String }

  select(e) {
    const tr = e.currentTarget
    if (!tr?.dataset.nodeId) return
    this.selectedId = tr.dataset.nodeId
    this.element.querySelectorAll("tr.tree-selected").forEach((r) => r.classList.remove("tree-selected"))
    tr.classList.add("tree-selected")
  }

  newFolder() { this._create("folder") }
  newItem() { this._create("item") }

  // 선택 노드 기준으로 생성(서버 apply_creation_context가 parent_id·position 결정) → 트리 인라인 명명
  _create(kind) {
    submitDynamicForm(this.createUrlValue, { "product[kind]": kind, relative_to: this.selectedId })
  }
}
