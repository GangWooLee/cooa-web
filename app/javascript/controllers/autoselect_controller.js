import { Controller } from "@hotwired/stimulus"

// 포커스 시 입력값 전체 선택 — 제안된 이름을 즉시 덮어쓰기 쉽게(onboarding 첫 작업실명 등).
// connect()는 autofocus로 이미 포커스된 값을 선택하고, focus->reselect는 이후 수동 재포커스를 커버한다.
export default class extends Controller {
  connect() { this.element.select?.() }
  reselect() { this.element.select?.() }
}
