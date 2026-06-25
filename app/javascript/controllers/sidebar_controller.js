import { Controller } from "@hotwired/stimulus"

// 좌측 사이드바 접기/펼치기 — <html> 클래스 토글 + 쿠키 영속(전체페이지 네비·리로드에도 유지, 무깜빡임)
export default class extends Controller {
  toggle() {
    const collapsed = document.documentElement.classList.toggle("sidebar-collapsed")
    document.cookie = `cooa_sidebar=${collapsed ? 1 : 0}; path=/; max-age=31536000; samesite=lax`
  }
}
