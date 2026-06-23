import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 행/카드 전체를 클릭하면 이동(내부 링크·버튼 클릭은 제외)
export default class extends Controller {
  static values = { url: String }

  go(event) {
    if (event.target.closest("a, button, input, [data-no-rowlink]")) return
    Turbo.visit(this.urlValue)
  }
}
