import { Controller } from "@hotwired/stimulus"

// 상단 히스토리 탭 — 클라이언트 즉각 반응(순수 가산, 서버 재렌더를 대기하지 않음):
//   (a) 네비게이션(turbo:load)마다 현재 경로와 각 탭 href를 비교해 활성/비활성 클래스·aria-current를 즉시 갱신.
//       서버 렌더 초기 상태(request.path == tab[:path])와 동일 결과 — SSR이 항상 정답이고, 여기선 전환만 앞당긴다.
//   (b) 닫기 ✕(button_to) 제출 시 해당 탭(+뒤 구분선)을 낙관적으로 숨김. 제출 자체는 가로채지 않고 그대로 발사.
//       실패 시 다음 풀 로드에서 서버 세션 상태로 자연 복원되므로 별도 롤백 로직이 필요 없다.
// JS 미동작 시에도 서버가 활성/비활성 클래스를 직접 렌더하므로 하이라이트는 정상 동작한다.
export default class extends Controller {
  static targets = ["tab"]
  static classes = ["active", "inactive"]

  connect() {
    this.highlight()
  }

  // turbo:load@document + 초기 connect에서 호출 — 현재 경로 기준으로 활성 탭 재계산(멱등).
  highlight() {
    const path = window.location.pathname
    this.tabTargets.forEach((tab) => {
      const link = tab.querySelector("a[href]")
      if (!link) return
      const active = new URL(link.href).pathname === path
      tab.classList.remove(...(active ? this.inactiveClasses : this.activeClasses))
      tab.classList.add(...(active ? this.activeClasses : this.inactiveClasses))
      if (active) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }

  // 닫기 ✕ 제출 시작 → 해당 탭과 뒤 구분선을 낙관적으로 숨김(제출은 그대로 진행).
  closeTab(event) {
    const tab = event.target.closest("[data-topbar-tabs-target='tab']")
    if (!tab) return
    tab.classList.add("hidden")
    tab.nextElementSibling?.classList.add("hidden") // 탭마다 뒤따르는 구분선도 함께 숨김(빈틈 방지)
  }
}
