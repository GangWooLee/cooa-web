require "test_helper"

# Locks the demo calibration (so the 95-test demo suite's green is intentional, not accidental) and
# FREEZES the Phase 1↔2 swap surface: policies depend only on roles_on returning ADR role_keys, so
# swapping User→Account changes nothing under app/policies.
class RoleResolverTest < ActiveSupport::TestCase
  setup { Rails.application.load_seed }

  test "demo operator (designer 김쿠아) → contributor+assignee+brand_admin" do
    kim = User.find_by(name: "김쿠아")
    roles = Authz::RoleResolver::DemoResolver.new(kim).roles_on(Product.new)
    assert_equal %w[assignee brand_admin contributor], roles.sort
  end

  test "RA (이쿠아) → ra_reviewer+approver (can approve others' runs)" do
    lee = User.find_by(name: "이쿠아")
    roles = Authz::RoleResolver::DemoResolver.new(lee).roles_on(Product.new)
    assert_equal %w[approver ra_reviewer], roles.sort
  end

  test "owner_id grants the owner role on owned products" do
    kim = User.find_by(name: "김쿠아")
    owned = Product.find_by(owner_id: kim.id)
    assert owned, "seed should give 김쿠아 at least one owned product"
    assert_includes Authz::RoleResolver::DemoResolver.new(kim).roles_on(owned), "owner"
  end

  test "RoleResolver.for swaps source by actor type (Phase 1↔2 seam)" do
    assert_instance_of Authz::RoleResolver::DemoResolver, Authz::RoleResolver.for(User.new)
    assert_instance_of Authz::RoleResolver::AssignmentResolver, Authz::RoleResolver.for(Account.new)
  end

  test "AssignmentResolver (Phase 2 stub) honors the roles_on(record) → [role_key] interface" do
    resolver = Authz::RoleResolver::AssignmentResolver.new(Account.new)
    assert_respond_to resolver, :roles_on
    assert_equal [], resolver.roles_on(Product.new)
  end

  # Phase 2a-1: AssignmentResolver is now the live app path (pundit_user = Current.account).
  test "AssignmentResolver reads role_assignment for a seeded account" do
    kim = Account.find_by!(email: "kim@cooa.dev")
    assert_equal %w[brand_admin owner],
                 Authz::RoleResolver::AssignmentResolver.new(kim).roles_on(Product.first).sort
    lee = Account.find_by!(email: "lee@cooa.dev")
    assert_equal %w[approver ra_reviewer],
                 Authz::RoleResolver::AssignmentResolver.new(lee).roles_on(Product.first).sort
  end

  # The SoD gate: an Account actor must report its linked user_id (bigint), not its own uuid, so
  # requested_by_id != actor_id compares in one space (else self-approval fails open — ADR-003).
  test "AccessContext#actor_id bridges an Account to its linked user_id" do
    kim_user = User.find_by!(name: "김쿠아")
    assert_equal kim_user.id, Authz::AccessContext.new(actor: kim_user.account).actor_id
    assert_equal kim_user.id, Authz::AccessContext.new(actor: kim_user).actor_id # bare User → own id
  end

  # ── Stage 2 D2: record-dependent scoped grants ──────────────────────────────────────────────
  def choi = Account.find_by!(email: "choi@partner.example") # external_collaborator scoped to CO0200
  def co0200 = Product.find_by!(code: "CO0200")
  def co0001 = Product.find_by!(code: "CO0001")

  # (a) a product-scope grant reaches the product, its components, and their versions.
  test "a product-scoped grant applies to the product and its descendants" do
    r = Authz::RoleResolver::AssignmentResolver.new(choi)
    comp = co0200.components.first
    ver  = comp.component_versions.first
    assert_includes r.roles_on(co0200), "external_collaborator"
    assert_includes r.roles_on(comp),   "external_collaborator"
    assert_includes r.roles_on(ver),    "external_collaborator"
  end

  # (b) it does NOT reach a different product's records.
  test "a product-scoped grant does not apply to other products" do
    r = Authz::RoleResolver::AssignmentResolver.new(choi)
    assert_empty r.roles_on(co0001)
    assert_empty r.roles_on(co0001.components.first)
  end

  # (c) memo-leak regression: the SAME resolver evaluating the scoped record then another product must
  # NOT carry the scoped role over (scoped_roles_for is never memoized; only tenant-wide is).
  test "scoped roles do not leak across records on one resolver" do
    r = Authz::RoleResolver::AssignmentResolver.new(choi)
    assert_includes r.roles_on(co0200), "external_collaborator" # evaluate scoped target first
    assert_empty r.roles_on(co0001),                            "scoped role must not leak to another product"
    assert_empty r.roles_on(co0001.components.first)
  end

  # (d) a component-scope grant reaches the component itself (Stage 1 chain bug) and its versions.
  test "a component-scoped grant applies to the component and its versions" do
    comp  = co0001.components.first
    other = co0001.components.second
    RoleAssignment.create!(account: choi, tenant_id: choi.tenant_id, role_key: "viewer",
                           scope_type: "component", scope_component_id: comp.id)
    r = Authz::RoleResolver::AssignmentResolver.new(choi)
    assert_includes r.roles_on(comp), "viewer"
    assert_includes r.roles_on(comp.component_versions.first), "viewer"
    assert_empty r.roles_on(other) # a sibling component the grant does not cover
  end

  # (e) tenant-wide grants are unchanged — they apply to every record (record-independent half).
  test "tenant-wide grants apply to every record" do
    kim = Account.find_by!(email: "kim@cooa.dev")
    r = Authz::RoleResolver::AssignmentResolver.new(kim)
    assert_equal %w[brand_admin owner], r.roles_on(co0200).sort
    assert_equal %w[brand_admin owner], r.roles_on(co0001).sort
  end

  # (f) Stage 2 D3 coherence with ProductPolicy::Scope: a product grant covers its whole SUBTREE for
  # AUTHORIZATION too (not just Scope visibility). A folder grant reaches descendant products (and their
  # components), so every row Scope surfaces is actually openable — no fail-closed drill-in.
  test "a product-scoped grant on a folder reaches descendant products (subtree coherence)" do
    retinol = Product.find_by!(name: "레티놀 3% 세럼") # 루트 폴더 → 미국 → [CO0000, CO0000L], 일본(CO0001)
    co0000  = Product.find_by!(code: "CO0000")
    RoleAssignment.create!(account: choi, tenant_id: choi.tenant_id, role_key: "external_collaborator",
                           scope_type: "product", scope_product_id: retinol.id)
    r = Authz::RoleResolver::AssignmentResolver.new(choi)
    assert_includes r.roles_on(retinol), "external_collaborator"                # 부여 노드 자신
    assert_includes r.roles_on(co0000),  "external_collaborator"                # 하위(손자) 제품도 개방 가능
    assert_includes r.roles_on(co0000.components.first), "external_collaborator" # 하위 제품의 구성요소도
  end
end
