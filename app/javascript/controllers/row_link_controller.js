import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 행 전체 클릭 시 행 내 프레임 링크를 클릭(상세 드로어 로드). 내부 링크·버튼 클릭은 제외.
export default class extends Controller {
  static targets = ["link"]
  static values = { url: String }

  go(event) {
    if (event.target.closest("a, button, input, [data-no-rowlink]")) return
    if (this.hasLinkTarget) return this.linkTarget.click()
    if (this.urlValue) Turbo.visit(this.urlValue)
  }
}
