# 셀프 프로필/보안 정책 — record가 인증된 액터 본인 계정일 때만 허용. 컨트롤러가 항상 current_account만
# 넘기므로 실질적으로 늘 참이나, 명시 인가로 strict verify_authorized 게이트(ADR-002 §0 BOLA 방어)를
# 충족하고 향후 param-id 회귀를 잠근다. 도메인 verb(PermissionMatrix)가 아니라 self 소유 판정이 게이트.
class ProfilePolicy < ApplicationPolicy
  def show? = own?
  def update? = own?
  def sign_out_all? = own?

  private

  def own? = record.is_a?(Account) && record.id.present? && record.id == context.actor&.id
end
