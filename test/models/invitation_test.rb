require "test_helper"

# Stage 3 (D2): an invitation can carry a typed scope (tenant | product | component) that the acceptance
# passes through to the created role_assignment. Invariants mirror RoleAssignment: scope_type agrees with
# which typed FK column is set, and a product/component scope must reference a row VISIBLE in THIS tenant
# (RLS makes a cross-tenant / non-existent id invisible → the membership check fails-closed, so an owner
# console can never scope an invite to another tenant's product). The DB CHECK inv_scope_coherence is the
# hard backstop; these lock the model mirror + the generate! seam.
class InvitationTest < ActiveSupport::TestCase
  setup do
    @org_id  = TenantConfig::DEMO_TENANT_ID # test_helper set Current.tenant_id to this
    @inviter = Account.create!(tenant_id: @org_id, email: "inviter@test", status: "active")
    @product = Product.create!(name: "P")
    @component = @product.components.create!(component_type: "outer_box", name: "box")
  end

  def build(**attrs)
    raw = SecureRandom.urlsafe_base64(8)
    Invitation.new({ tenant_id: @org_id, email: "invitee-#{raw}@partner.dev", role_key: "contributor",
                     invited_by_account_id: @inviter.id, token_digest: Invitation.digest(raw),
                     expires_at: 7.days.from_now, scope_type: "tenant" }.merge(attrs))
  end

  test "scope_type defaults to tenant" do
    assert_equal "tenant", Invitation.new.scope_type
  end

  test "tenant invitation with no typed scope is valid" do
    assert build(scope_type: "tenant").valid?
  end

  test "tenant invitation that sets a typed scope is invalid" do
    refute build(scope_type: "tenant", scope_product_id: @product.id).valid?
  end

  test "product invitation requires scope_product_id and forbids scope_component_id" do
    assert build(scope_type: "product", scope_product_id: @product.id).valid?
    refute build(scope_type: "product").valid?
    refute build(scope_type: "product", scope_product_id: @product.id, scope_component_id: @component.id).valid?
  end

  test "component invitation requires scope_component_id and forbids scope_product_id" do
    assert build(scope_type: "component", scope_component_id: @component.id).valid?
    refute build(scope_type: "component").valid?
    refute build(scope_type: "component", scope_component_id: @component.id, scope_product_id: @product.id).valid?
  end

  test "product scope must reference a product visible in this tenant (cross-tenant/non-existent → invalid)" do
    inv = build(scope_type: "product", scope_product_id: 999_999_999)
    refute inv.valid?
    assert inv.errors[:scope_product_id].present?
  end

  test "component scope must reference a component visible in this tenant" do
    inv = build(scope_type: "component", scope_component_id: 999_999_999)
    refute inv.valid?
    assert inv.errors[:scope_component_id].present?
  end

  # Cross-tenant defense must be VERIFIABLE on the owner connection (test env bypasses RLS): the explicit
  # tenant_id match rejects a REAL product/component that lives in ANOTHER tenant — not merely a non-existent
  # id. Under the old `where(id:).exists?` this passed (owner sees all tenants) → the defense was untestable.
  test "product scope in another tenant is rejected (explicit tenant_id match, owner-connection verifiable)" do
    other_org = Organization.create!(name: "Other Tenant", region: "US")
    other_product = Product.create!(tenant_id: other_org.id, name: "OtherP", kind: "folder")
    inv = build(scope_type: "product", scope_product_id: other_product.id)
    refute inv.valid?
    assert inv.errors[:scope_product_id].present?
  end

  test "DB CHECK inv_scope_coherence backstops a validation bypass" do
    incoherent = build(scope_type: "product") # product scope w/o product id — model would reject
    assert_raises(ActiveRecord::StatementInvalid) { incoherent.save!(validate: false) }
  end

  test "generate! carries scope through to the persisted invitation" do
    inv, raw = Invitation.generate!(email: "scoped@partner.dev", role_key: "external_collaborator",
                                    invited_by_account_id: @inviter.id,
                                    scope_type: "product", scope_product_id: @product.id)
    assert raw.present?
    assert_equal "product", inv.scope_type
    assert_equal @product.id, inv.scope_product_id
  end

  test "generate! defaults to a tenant-wide invitation (no scope)" do
    inv, = Invitation.generate!(email: "tw@partner.dev", role_key: "contributor", invited_by_account_id: @inviter.id)
    assert_equal "tenant", inv.scope_type
    assert_nil inv.scope_product_id
  end

  # 정보 노출 회귀(리뷰 blocking): 재초대 제안은 caller가 넘긴 scope(관리자 가시 서브트리) 안의 과거 초대만 낸다.
  # 무-스코프면 형제 서브트리의 관할 밖 이메일(PII)이 스코프 admin에게 열거된다 — @workspace_pending과 동형 스코프.
  test "suggestion_emails only proposes past invites within the given (subtree) scope" do
    product_b = Product.create!(name: "PB")
    build(scope_type: "product", scope_product_id: @product.id,
          email: "reinvite-a@partner.dev", revoked_at: Time.current).save!
    build(scope_type: "product", scope_product_id: product_b.id,
          email: "reinvite-b@partner.dev", revoked_at: Time.current).save!

    suggestions = Invitation.suggestion_emails(Invitation.where(scope_product_id: @product.id))

    assert_includes suggestions, "reinvite-a@partner.dev"     # 관할 안 재초대 후보는 제안
    assert_not_includes suggestions, "reinvite-b@partner.dev" # 형제 서브트리 이메일은 관할 밖 → 미노출
  end
end
