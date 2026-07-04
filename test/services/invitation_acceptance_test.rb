require "test_helper"

# Stage 3 (D3): InvitationAcceptance passes the invitation's typed scope THROUGH to the created
# role_assignment. A product-scoped invite must yield a PRODUCT-scoped grant — never a tenant-wide one
# (the Stage-2 hazard: the old hardcoded scope_type:"tenant" would have granted the whole tenant to an
# external agency). A tenant invite still yields a tenant-wide grant (unchanged). Audit carries the scope.
class InvitationAcceptanceTest < ActiveSupport::TestCase
  setup do
    @org_id  = TenantConfig::DEMO_TENANT_ID
    @inviter = Account.create!(tenant_id: @org_id, email: "inviter@svc.test", status: "active")
    @product = Product.create!(name: "스코프 제품")
  end

  def auth_for(email:, uid: nil, name: "새 협력자")
    OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid || "svc-#{SecureRandom.hex(4)}",
                           info: { email: email, name: name })
  end

  test "product-scoped invitation → product-scoped grant (NOT tenant-wide)" do
    inv, = Invitation.generate!(email: "agency@partner.dev", role_key: "external_collaborator",
                                invited_by_account_id: @inviter.id,
                                scope_type: "product", scope_product_id: @product.id)
    account = InvitationAcceptance.call(invitation: inv, auth: auth_for(email: "agency@partner.dev"))
    assert account, "수락은 성공해야"
    ra = account.role_assignments.sole
    assert_equal "external_collaborator", ra.role_key
    assert_equal "product", ra.scope_type
    assert_equal @product.id, ra.scope_product_id
    refute ra.tenant_wide?, "스코프 초대가 tenant-wide grant를 만들면 안 됨(전 테넌트 유출 회귀)"
    assert_equal @inviter.id, ra.granted_by
    assert_equal "designer", account.user.role, "external_collaborator 표시 role은 시드 choi 관례(designer)"
  end

  test "tenant invitation → tenant-wide grant (unchanged) + audit carries scope" do
    inv, = Invitation.generate!(email: "member@partner.dev", role_key: "contributor",
                                invited_by_account_id: @inviter.id)
    account = InvitationAcceptance.call(invitation: inv, auth: auth_for(email: "member@partner.dev"))
    ra = account.role_assignments.sole
    assert_equal "contributor", ra.role_key
    assert ra.tenant_wide?
    assert_equal "pm", account.user.role, "비-external_collaborator는 기존 표시 기본(pm) 유지"
    audit = AuditLog.where(action: "invitation.accept", outcome: "allow").order(:ts).last
    assert_equal "tenant", audit.after["scope_type"]
  end

  test "audit after records the product scope for a scoped acceptance" do
    inv, = Invitation.generate!(email: "agency2@partner.dev", role_key: "external_collaborator",
                                invited_by_account_id: @inviter.id,
                                scope_type: "product", scope_product_id: @product.id)
    InvitationAcceptance.call(invitation: inv, auth: auth_for(email: "agency2@partner.dev"))
    audit = AuditLog.where(action: "invitation.accept", outcome: "allow").order(:ts).last
    assert_equal "product", audit.after["scope_type"]
    assert_equal @product.id, audit.after["scope_product_id"]
  end
end
