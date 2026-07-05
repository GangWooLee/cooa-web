import { Controller } from "@hotwired/stimulus"

// 홈 "새 작업실" 모달(D3) — 열기 시 이름 입력 autofocus. Esc/백드롭 닫기는 <dialog> 네이티브 동작.
// 제출은 내부 form(workspaces#create) — 이름 필수 + 선택 멤버(4종). 취소는 close.
export default class extends Controller {
  static targets = ["dialog", "name"]

  open() {
    this.dialogTarget.showModal()
    if (this.hasNameTarget) this.nameTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }
}
