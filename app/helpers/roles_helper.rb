module RolesHelper
  # 역할 키 → 한글 라벨(배지·옵션 공용). value(role_key)는 불변 — 표시만 한글화(D4).
  def role_label(role_key) = Authz::RoleLabels.label(role_key)
  def role_description(role_key) = Authz::RoleLabels.description(role_key)

  # 역할 select의 <option> 묶음 — 옵션 텍스트에 "라벨 · 능력설명"을 가시화(hover title에만 두지 않음·D4
  # 명확화). keys로 노출 역할 집합을 정한다(작업실 폼 = WORKSPACE_ROLE_KEYS 4종 · 전사 폼 = INVITABLE 7종).
  def role_option_tags(keys, selected: nil)
    safe_join(keys.map do |rk|
      desc = role_description(rk)
      text = desc ? "#{role_label(rk)} · #{desc}" : role_label(rk)
      tag.option(text, value: rk, title: desc, selected: rk.to_s == selected.to_s)
    end)
  end
end
