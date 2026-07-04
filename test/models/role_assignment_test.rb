require "test_helper"

# Stage 2 (D1b): the typed-scope invariants — scope_type must agree with which typed FK column is set,
# owner is tenant-wide by construction, and tenant_wide selects only unscoped grants. The DB CHECK
# ra_scope_coherence is the hard backstop; these lock the model mirror + the scope.
class RoleAssignmentTest < ActiveSupport::TestCase
  setup do
    @org_id = TenantConfig::DEMO_TENANT_ID # test_helper set Current.tenant_id to this
    @account = Account.create!(tenant_id: @org_id, email: "ra-model@test", status: "active")
    @product = Product.create!(name: "P")
    @component = @product.components.create!(component_type: "outer_box", name: "box")
  end

  def build(**attrs)
    RoleAssignment.new({ account: @account, tenant_id: @org_id, role_key: "viewer", scope_type: "tenant" }.merge(attrs))
  end

  test "tenant grant with no typed scope is valid" do
    assert build(scope_type: "tenant").valid?
  end

  test "tenant grant that sets a typed scope is invalid" do
    refute build(scope_type: "tenant", scope_product_id: @product.id).valid?
  end

  test "product grant requires scope_product_id and forbids scope_component_id" do
    assert build(scope_type: "product", scope_product_id: @product.id).valid?
    refute build(scope_type: "product").valid?
    refute build(scope_type: "product", scope_product_id: @product.id, scope_component_id: @component.id).valid?
  end

  test "component grant requires scope_component_id and forbids scope_product_id" do
    assert build(scope_type: "component", scope_component_id: @component.id).valid?
    refute build(scope_type: "component").valid?
    refute build(scope_type: "component", scope_component_id: @component.id, scope_product_id: @product.id).valid?
  end

  test "owner grants must be tenant-wide" do
    refute build(role_key: "owner", scope_type: "product", scope_product_id: @product.id).valid?
    assert build(role_key: "owner", scope_type: "tenant").valid?
  end

  test "tenant_wide scope selects only unscoped grants" do
    tw = RoleAssignment.create!(account: @account, tenant_id: @org_id, role_key: "viewer", scope_type: "tenant")
    scoped = RoleAssignment.create!(account: @account, tenant_id: @org_id, role_key: "external_collaborator",
                                    scope_type: "product", scope_product_id: @product.id)
    assert_includes RoleAssignment.tenant_wide, tw
    refute_includes RoleAssignment.tenant_wide, scoped
    assert tw.tenant_wide?
    refute scoped.tenant_wide?
  end

  test "DB CHECK ra_scope_coherence backstops a validation bypass" do
    incoherent = build(scope_type: "product") # product scope w/o product id — model would reject
    assert_raises(ActiveRecord::StatementInvalid) { incoherent.save!(validate: false) }
  end

  # A scoped owner grant is scope-COHERENT (passes ra_scope_coherence) yet breaks the "owner ⇒ tenant-wide"
  # invariant that LastOwnerGuard/EligibleApproverService assume. Only ra_owner_tenant_wide (m4) rejects it
  # once the model validation is bypassed (update_all / raw insert).
  test "DB CHECK ra_owner_tenant_wide backstops a validation bypass" do
    scoped_owner = build(role_key: "owner", scope_type: "product", scope_product_id: @product.id)
    assert_raises(ActiveRecord::StatementInvalid) { scoped_owner.save!(validate: false) }
  end
end
