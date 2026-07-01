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

# SoD lives in ApprovalRequestPolicy (버전 리뷰), not the matrix — verified with a stub request.
# confirm_review? = can?(:approve) && pending? && actor_present? && submitter_distinct?
class ApprovalRequestSoDTest < ActiveSupport::TestCase
  StubContext = Struct.new(:roles, :actor_id) do
    def roles_on(_record) = roles
  end
  Req = Struct.new(:submitter_id, :status, :requested_reviewer_ids) do
    def pending? = status == "pending"
  end

  def policy(roles, actor_id, submitter_id, status: "pending", requested: [])
    ApprovalRequestPolicy.new(StubContext.new(roles, actor_id), Req.new(submitter_id, status, requested))
  end

  test "reviewer who is not the requester may confirm" do
    assert policy(%w[approver], 2, 1).confirm_review?
  end

  # 소프트 게이트: 요청받은 리뷰어는 approve verb가 없어도(예: contributor) 확인 가능("요청받음=권한").
  test "requested reviewer without approve verb may confirm (soft grant)" do
    assert policy(%w[contributor], 2, 1, requested: [2]).confirm_review?
  end

  # SoD는 요청받아도 하드: 요청자 본인이 리뷰어로 지정돼도 자기 확인 불가.
  test "requested reviewer who is the requester is still SoD-blocked" do
    refute policy(%w[contributor], 1, 1, requested: [1]).confirm_review?
  end

  test "requester is denied (SoD)" do
    refute policy(%w[approver], 1, 1).confirm_review?
  end

  test "owner is not exempt from SoD" do
    refute policy(%w[owner], 1, 1).confirm_review?
  end

  test "non-reviewer role cannot confirm even if distinct" do
    refute policy(%w[contributor], 2, 1).confirm_review?
  end

  test "nil actor (unlinked Account) fails closed" do
    refute policy(%w[approver], nil, 1).confirm_review?
  end

  test "a non-pending request cannot be confirmed" do
    refute policy(%w[approver], 2, 1, status: "reviewed").confirm_review?
  end
end
