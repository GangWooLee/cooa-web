require "test_helper"

# Validates the authorization LOGIC independent of the demo identity: roles are injected via a stub
# context, so these assert the ADR-002 §6 matrix + §8.2 SoD directly (no DB, no resolver).
class PolicyMatrixTest < ActiveSupport::TestCase
  StubContext = Struct.new(:roles, :actor_id) do
    def roles_on(_record) = roles
  end

  def policy(roles, record: Object.new) = ApplicationPolicy.new(StubContext.new(roles, 1), record)

  test "viewer may read but not mutate or approve" do
    p = policy(%w[viewer])
    assert p.view_product?
    assert p.view_screening_findings?
    refute p.manage_product?
    refute p.run_screening?
    refute p.approve?
  end

  test "contributor uploads/screens but cannot manage members or approve" do
    p = policy(%w[contributor])
    assert p.upload_version?
    assert p.run_screening?
    refute p.manage_members?
    refute p.approve?
  end

  test "approver holds approve verb; contributor and assignee do not" do
    assert policy(%w[approver]).approve?
    refute policy(%w[contributor]).approve?
    refute policy(%w[assignee]).approve?
  end

  test "brand_admin manages members but cannot approve (SoD separation)" do
    p = policy(%w[brand_admin])
    assert p.manage_members?
    refute p.approve?
  end

  test "unknown verb raises (typo guard)" do
    assert_raises(ArgumentError) { policy(%w[owner]).can?(:bogus_verb) }
  end

  test "matrix completeness — every verb in the matrix is a registered action" do
    Authz::PermissionMatrix::MATRIX.each do |role, verbs|
      verbs.each { |v| assert Authz::Actions.valid?(v), "matrix verb #{v.inspect} (#{role}) not in Actions" }
    end
  end

  test "every CORE+SI_LEAN action is granted to at least one role" do
    granted = Authz::PermissionMatrix::MATRIX.values.flatten.uniq
    (Authz::Actions::CORE + Authz::Actions::SI_LEAN).each do |a|
      assert_includes granted, a, "action #{a} is granted to no role"
    end
  end
end

# SoD lives in ScreeningRunPolicy, not the matrix — verified with a stub run.
class ScreeningRunSoDTest < ActiveSupport::TestCase
  StubContext = Struct.new(:roles, :actor_id) do
    def roles_on(_record) = roles
  end
  Run = Struct.new(:requested_by_id)

  def policy(roles, actor_id, requested_by_id)
    ScreeningRunPolicy.new(StubContext.new(roles, actor_id), Run.new(requested_by_id))
  end

  test "approver who is not the submitter may approve" do
    assert policy(%w[approver], 2, 1).approve?
  end

  test "approver who IS the submitter is denied (SoD)" do
    refute policy(%w[approver], 1, 1).approve?
  end

  test "owner is not exempt from SoD" do
    refute policy(%w[owner], 1, 1).approve?
  end

  test "non-approver role cannot approve even if distinct" do
    refute policy(%w[contributor], 2, 1).approve?
  end
end
