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
end
