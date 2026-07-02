import { Controller } from "@hotwired/stimulus"

// 초대 링크 복사(멤버 페이지). sourceValue를 클립보드에 쓰고 버튼 라벨을 잠시 "복사됨"으로.
export default class extends Controller {
  static values = { source: String }
  static targets = ["button"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceValue)
      this.flash("복사됨 ✓")
    } catch (_) {
      // 비보안 컨텍스트/권한 거부 — 선택 가능한 텍스트가 옆에 있으므로 수동 복사 안내만
      this.flash("복사 실패 — 링크를 직접 선택하세요")
    }
  }

  flash(text) {
    const btn = this.hasButtonTarget ? this.buttonTarget : null
    if (!btn) return
    const orig = btn.textContent
    btn.textContent = text
    setTimeout(() => { btn.textContent = orig }, 1500)
  }
}
