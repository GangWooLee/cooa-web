import { Controller } from "@hotwired/stimulus"

// 폼 제출 시 지정 버튼을 로딩 상태로 — disable + 스피너 + 라벨 교체. 중복 제출 가드(loading).
//  폼:  data-controller="submit-loading"
//       data-action="submit->submit-loading#onSubmit"
//       data-submit-loading-label-value="처리 중…"   (생략 시 기존 버튼 텍스트 유지)
//  버튼: data-submit-loading-target="button"          (반드시 <button> — innerHTML 교체)
// 제출 이벤트 발생 후 disable → 폼 제출은 이미 진행 중이라 취소되지 않는다. 성공=풀 네비/리다이렉트로
// 새 버튼 렌더, Turbo 422 재렌더 시에도 서버가 새 버튼을 그려 상태가 리셋된다.
export default class extends Controller {
  static targets = ["button"]
  static values = { label: String }

  onSubmit() {
    if (this.loading || !this.hasButtonTarget) return
    this.loading = true
    const btn = this.buttonTarget
    const label = this.hasLabelValue && this.labelValue ? this.labelValue : btn.textContent.trim()
    btn.innerHTML = `<span class="spinner" aria-hidden="true"></span> ${this.escape(label)}`
    btn.disabled = true
    btn.setAttribute("aria-busy", "true")
  }

  escape(s) {
    const d = document.createElement("div")
    d.textContent = s
    return d.innerHTML
  }
}
