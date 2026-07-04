# 멤버 관리(로스터·초대·grant 발급/회수)의 2단 인가(Stage 4 T3). members·invitations·role_assignments가
# 공유한다. 핵심: scoped brand_admin은 조직 레코드로는 인가되지 않으므로(AdminScope 참조) tenant-wide면
# 조직 레코드로 · scoped면 자기 브랜드 제품 레코드로 authorize한다. Pundit verify_authorized는 정직하게
# 충족(skip 없음·policy 메서드 신설 없음)하고, deny는 기존 규약(GET html 303 · 그 외 403 + 감사)을 탄다.
module MemberAdministration
  extend ActiveSupport::Concern

  private

  # 로스터 열람 진입 게이트. tenant_verb = 조직 레벨 verb(index=:list_tenant_accounts?).
  # 반환: AdminScope 결과(:all | [Product,…] | nil). nil이면 조직 authorize가 deny를 낸다(비관리자 차단).
  def authorize_member_read!(tenant_verb)
    scope = Authz::AdminScope.for(current_account)
    if scope.is_a?(Array)
      authorize scope.first, :manage_members? # scoped brand_admin: 자기 브랜드 루트 제품 레코드로(정직)
    else
      authorize current_organization, tenant_verb # :all 통과 · nil은 여기서 deny
    end
    scope
  end

  # 초대·grant 발급/회수의 2단 인가 + 브랜드 스코프 강제. scoped brand_admin은 "대상 제품" 레코드로
  # authorize → 자기 브랜드 서브트리 밖(타 브랜드)이면 roles_on 공집합으로 자연 deny(403), tenant-wide
  # (스코프 없는) 발급은 대상 제품이 없어 조직 레코드로 fallback → scoped admin은 tenant-wide manage_members
  # 부재로 deny. :all(tenant-wide admin)은 조직 레코드(스코프 자유·현행 무회귀). 서버측 강제(UI 숨김 무의존).
  def authorize_member_write!(scope_product_id)
    if Authz::AdminScope.for(current_account).is_a?(Array)
      target = scope_product_id.present? ? Product.find(scope_product_id) : current_organization
      authorize target, :manage_members?
    else
      authorize current_organization, :manage_members?
    end
  end
end
