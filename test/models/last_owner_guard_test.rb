require "test_helper"

# P6 #3 — the tenant-availability invariant: a tenant must always keep >=1 active owner. A fresh tenant
# is used so the count is independent of the demo seed.
class LastOwnerGuardTest < ActiveSupport::TestCase
  setup do
    @org = Organization.create!(name: "Guard Tenant", region: "JP")
    @u1 = User.create!(name: "오너1", role: "ra", avatar_color: "#111111", email: "o1@guard.test")
    @a1 = Account.create!(tenant_id: @org.id, user: @u1, email: "o1@guard.test", status: "active")
    @owner1 = RoleAssignment.create!(tenant_id: @org.id, account: @a1, role_key: "owner", scope_type: "tenant")
    @a2 = Account.create!(tenant_id: @org.id, email: "c@guard.test", status: "active") # not an owner yet
  end

  def make_second_owner!
    RoleAssignment.create!(tenant_id: @org.id, account: @a2, role_key: "owner", scope_type: "tenant")
  end

  test "suspending the LAST active owner is refused" do
    assert_raises(LastOwnerGuard::Error) { @a1.update!(status: "suspended") }
    assert_equal "active", @a1.reload.status, "the refused suspend rolled back"
  end

  test "deprovisioning the LAST active owner is refused" do
    assert_raises(LastOwnerGuard::Error) { @a1.update!(status: "deprovisioned") }
  end

  test "suspending an owner is allowed when another active owner remains" do
    make_second_owner!
    assert_nothing_raised { @a1.update!(status: "suspended") }
    assert_equal "suspended", @a1.reload.status
  end

  test "an owner whose peer is only SUSPENDED is still the last active owner — refused" do
    make_second_owner!
    @a2.update!(status: "suspended") # @a2 no longer counts as active
    assert_raises(LastOwnerGuard::Error) { @a1.update!(status: "suspended") }
  end

  test "removing the LAST owner grant is refused" do
    assert_raises(LastOwnerGuard::Error) { @owner1.destroy! }
    assert RoleAssignment.exists?(@owner1.id), "the grant survives the refused destroy"
  end

  test "expiring the LAST owner grant is refused" do
    assert_raises(LastOwnerGuard::Error) { @owner1.update!(expires_at: 1.hour.ago) }
  end

  test "destroying the LAST owner account is refused (cascade hits the grant guard)" do
    assert_raises(LastOwnerGuard::Error) { @a1.destroy! }
    assert Account.exists?(@a1.id)
  end

  test "a non-owner account suspends freely" do
    assert_nothing_raised { @a2.update!(status: "suspended") }
  end
end
