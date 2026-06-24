// 공용 DOM/폼 유틸 — 여러 Stimulus 컨트롤러의 중복(동적 폼 제출·CSRF 토큰) 제거.

export function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content
}

// 동적 <form>을 만들어 Turbo(_top)로 제출 = redirect-after-mutation. 제출 후 폼 제거(DOM 누수 방지).
// fields: { name: value } (value가 null/undefined면 생략). _method:"delete" 등 지원.
export function submitDynamicForm(action, fields = {}, { frame = "_top" } = {}) {
  const form = document.createElement("form")
  form.method = "post"
  form.action = action
  form.dataset.turboFrame = frame
  const all = { ...fields, authenticity_token: csrfToken() }
  for (const [name, value] of Object.entries(all)) {
    if (value == null) continue
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }
  document.body.appendChild(form)
  form.addEventListener("submit", () => queueMicrotask(() => form.remove()), { once: true })
  form.requestSubmit()
}
