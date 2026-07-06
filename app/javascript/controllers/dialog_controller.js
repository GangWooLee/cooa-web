import { Controller } from "@hotwired/stimulus"

// 모달 <dialog> 열기/닫기 — 새 작업실 모달·작업실 멤버 모달 공용(구 workspace-create·popover 통합). open 시
// autofocus 타깃이 있으면 포커스. openValue=true면 connect에서 자동 열림(초대 발급 직후 flash[:invite_link] —
// 링크 배너를 온 자리에서 노출). native Esc/백드롭 닫기는 <dialog>가 담당(별도 dismissable 불요).
export default class extends Controller {
  static targets = ["dialog", "autofocus"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    if (this.hasAutofocusTarget) this.autofocusTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }
}
