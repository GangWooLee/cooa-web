# 초대 수락 = 원자 온보딩. 호출 전제(sessions#accept_invitation_signup이 보장): email_verified 검증됨
# + 초대 email == 검증된 로그인 email. 여기서는 클레임(레이스 승자 1명)과 3-레코드 생성 + 감사를
# 하나의 트랜잭션으로 묶는다. 실패는 nil 반환 → 콜러가 generic reject(열거 방지).
class InvitationAcceptance
  AVATAR_PALETTE = %w[#8e0300 #4f74e3 #d99a00 #5f8f2e #8e5aa8 #2a7f8e].freeze

  def self.call(invitation:, auth:)
    result = ApplicationRecord.transaction do
      # 원자 클레임 선행 — 동시 수락/재사용은 여기서 정확히 1명만 통과.
      raise ActiveRecord::Rollback unless invitation.claim!

      # User = 도메인 '사람'(SoD actor_id·감사 fail-closed에 필수). role은 표시용 enum(authz는 RoleAssignment).
      # external_collaborator는 시드 choi 관례(designer) 재사용, 그 외는 기존 표시 기본(pm) — 순수 표시용.
      user = User.create!(
        name: auth.info&.name.presence || invitation.email.split("@").first,
        email: invitation.email, role: (invitation.role_key == "external_collaborator" ? "designer" : "pm"),
        avatar_color: AVATAR_PALETTE[invitation.email.sum % AVATAR_PALETTE.size]
      )
      # 생성과 동시에 (provider, subject) 바인딩 — bind 단계 불필요. (tenant,email) 유니크가 중복 백스톱.
      account = Account.create!(
        tenant_id: Current.tenant_id, user: user, email: invitation.email, status: "active",
        idp_provider: auth.provider.to_s, idp_subject: auth.uid
      )
      # Stage 3 (D3): pass the invitation's typed scope THROUGH — a product-scoped invite → product-scoped
      # grant (외부 에이전시 = 제품 한정), a tenant invite → tenant-wide (unchanged). RoleAssignment's model
      # validations (scope coherence + tenant-membership) + the DB CHECK are the backstops.
      RoleAssignment.create!(
        account: account, tenant_id: Current.tenant_id, role_key: invitation.role_key,
        scope_type: invitation.scope_type,
        scope_product_id: invitation.scope_product_id, scope_component_id: invitation.scope_component_id,
        granted_by: invitation.invited_by_account_id, granted_at: Time.current
      )
      invitation.update!(accepted_account_id: account.id)

      # 감사: actor = 방금 온보딩된 수락자 본인(User 생성됨 → domain actor 존재, fail-closed 통과).
      # resource_id는 bigint 도메인 공간(관례) — uuid PK인 invitation은 after 페이로드로 식별.
      Current.account = account
      AuditLog.record!(action: "invitation.accept", resource_type: "Invitation",
                       resource_id: nil, outcome: "allow",
                       after: { invitation_id: invitation.id, email: invitation.email, role_key: invitation.role_key,
                                scope_type: invitation.scope_type, scope_product_id: invitation.scope_product_id,
                                scope_component_id: invitation.scope_component_id })
      account
    end
    result || nil
  end
end
