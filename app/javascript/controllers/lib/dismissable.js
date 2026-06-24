// 공용 dismiss 동작 — 바깥클릭/Esc(+옵션 scroll)로 controller.hide() 호출. menu/tree_ctx 중복 제거.
// contains: 바깥 판정 영역(기본 controller.element). onScroll: 스크롤 시 닫기.
export function bindDismiss(controller, { contains, onScroll = false } = {}) {
  const inside = contains || ((target) => controller.element.contains(target))
  controller._dismiss = {
    click: (e) => { if (!inside(e.target)) controller.hide() },
    key: (e) => { if (e.key === "Escape") controller.hide() },
    scroll: onScroll ? () => controller.hide() : null
  }
  document.addEventListener("click", controller._dismiss.click)
  document.addEventListener("keydown", controller._dismiss.key)
  if (controller._dismiss.scroll) document.addEventListener("scroll", controller._dismiss.scroll, true)
}

export function unbindDismiss(controller) {
  const d = controller._dismiss
  if (!d) return
  document.removeEventListener("click", d.click)
  document.removeEventListener("keydown", d.key)
  if (d.scroll) document.removeEventListener("scroll", d.scroll, true)
}
