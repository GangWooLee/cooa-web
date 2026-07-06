import { Controller } from "@hotwired/stimulus"
import { bindDismiss, unbindDismiss } from "controllers/lib/dismissable"

// details/summary 팝오버 — Esc·바깥클릭으로 닫기(native summary 토글은 그대로 유지). 멤버 관리 어포던스 등.
// controller.element = <details>. dismissable(menu/tree_ctx 공용)이 바깥 판정을 element.contains로 수행하므로
// summary·패널 내부 클릭은 닫지 않고 바깥/Esc만 open 속성을 제거한다.
export default class extends Controller {
  connect() { bindDismiss(this) }
  disconnect() { unbindDismiss(this) }
  hide() { this.element.removeAttribute("open") }
}
