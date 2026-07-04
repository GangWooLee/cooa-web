require "test_helper"

# Stage 2 (D3): ProductPolicy::Scope decides which of the tenant's products a scope-limited account may
# see. Tenant-wide (and the demo User path) keep full scope; a scoped account is confined to its granted
# subtree; an account with no grants sees nothing (fail-closed).
class ProductPolicyTest < ActiveSupport::TestCase
  setup { Rails.application.load_seed }

  def scope_for(account)
    ProductPolicy::Scope.new(Authz::AccessContext.new(actor: account), Product.all).resolve
  end

  def fresh_account(email)
    Account.create!(tenant_id: TenantConfig::DEMO_TENANT_ID, email: email, status: "active")
  end

  def roles_on(account, record)
    Authz::RoleResolver::AssignmentResolver.new(account).roles_on(record)
  end

  test "a tenant-wide account sees every product (no regression)" do
    kim = Account.find_by!(email: "kim@cooa.dev")
    assert_equal Product.count, scope_for(kim).count
  end

  test "a product-scoped account sees only that product's subtree" do
    choi = Account.find_by!(email: "choi@partner.example") # scoped to CO0200 (a leaf)
    assert_equal %w[CO0200], scope_for(choi).pluck(:code).compact
    refute_includes scope_for(choi).pluck(:id), Product.find_by!(code: "CO0001").id
  end

  test "a product-scoped grant on a folder expands to all descendants" do
    acct = fresh_account("folder-scope@test")
    retinol = Product.find_by!(name: "레티놀 3% 세럼") # root folder → 미국 → [CO0000, CO0000L], 일본(CO0001)
    RoleAssignment.create!(account: acct, tenant_id: acct.tenant_id, role_key: "external_collaborator",
                           scope_type: "product", scope_product_id: retinol.id)
    visible = scope_for(acct).to_a
    assert_includes visible.map(&:id), retinol.id
    %w[CO0000 CO0000L CO0001].each { |c| assert_includes visible.map(&:code), c }
    refute_includes visible.map(&:code), "CO0200" # a different brand — not visible
  end

  # Coherence invariant "every surfaced product row is openable": ProductPolicy::Scope surfaces a component
  # grant's owning product, and the RoleResolver must AUTHORIZE opening it — else the row shows in the tree
  # but drill-in fails closed (redirect to root). Assert BOTH halves, not just surfacing.
  test "a component-scoped grant surfaces AND opens the component's owning product" do
    acct = fresh_account("comp-scope@test")
    comp = Product.find_by!(code: "CO0000").components.first
    RoleAssignment.create!(account: acct, tenant_id: acct.tenant_id, role_key: "external_collaborator",
                           scope_type: "component", scope_component_id: comp.id)

    assert_equal %w[CO0000], scope_for(acct).pluck(:code).compact                 # surfaced by Scope …
    refute_empty roles_on(acct, comp.product), "surfaced product must be openable" # … and openable.
  end

  # The openability fix must be EXACT: it opens the owning product without bleeding to a sibling component or
  # leaking to another product (memo key [pid, cid] stays a pure function). CO0001 has ≥2 components.
  test "a component-scoped grant authorizes exactly its component subtree + owning product" do
    acct = fresh_account("comp-exact@test")
    product = Product.find_by!(code: "CO0001")
    granted = product.components.first
    sibling = product.components.second
    other   = Product.find_by!(code: "CO0000")
    RoleAssignment.create!(account: acct, tenant_id: acct.tenant_id, role_key: "viewer",
                           scope_type: "component", scope_component_id: granted.id)
    r = Authz::RoleResolver::AssignmentResolver.new(acct)

    assert_includes r.roles_on(product), "viewer"                          # (a) owning Product opens
    assert_includes r.roles_on(granted), "viewer"                          # (b) granted component …
    assert_includes r.roles_on(granted.component_versions.first), "viewer" #     … and its version
    assert_empty r.roles_on(sibling), "a sibling component must not open"  # (c) same product, other component
    assert_empty r.roles_on(other), "another product must not leak"        # (d) other product record …
    assert_empty r.roles_on(other.components.first), "no cross-product leak" #   … and its component
  end

  test "an account with no grants sees nothing (fail-closed)" do
    assert_empty scope_for(fresh_account("no-grant@test"))
  end

  test "a non-Account actor (demo User path) keeps full scope" do
    kim_user = User.find_by!(name: "김쿠아")
    full = ProductPolicy::Scope.new(Authz::AccessContext.new(actor: kim_user), Product.all).resolve
    assert_equal Product.count, full.count
  end
end
