import { Controller } from "@hotwired/stimulus"

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
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.createUrlValue
    form.dataset.turboFrame = "_top"
    this._hidden(form, "product[kind]", kind)
    if (this.selectedId) this._hidden(form, "relative_to", this.selectedId)
    const token = document.querySelector("meta[name='csrf-token']")?.content
    if (token) this._hidden(form, "authenticity_token", token)
    document.body.appendChild(form)
    form.requestSubmit()
  }

  _hidden(form, name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }
}
