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
    assert policy(%w[contributor], 2, 1, requested: [ 2 ]).confirm_review?
  end

  # SoD는 요청받아도 하드: 요청자 본인이 리뷰어로 지정돼도 자기 확인 불가.
  test "requested reviewer who is the requester is still SoD-blocked" do
    refute policy(%w[contributor], 1, 1, requested: [ 1 ]).confirm_review?
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

# claim(자기배정)의 SoD — confirm과 달리 HARD approve verb 필요(소프트게이트 미적용): 미배정 pending 리뷰를
# 테넌트 owner/approver가 스스로 맡는다. claim? = can?(:approve) && pending? && actor_present? &&
# submitter_distinct? && requested_reviewer_ids.none?. 리뷰어가 이미 있는 요청(타인 배정 포함)은 미배정이
# 아니므로 claim 대상 아님 — 이미 지정된 리뷰어는 Segment A(내게 요청된 리뷰) 소속.
class ApprovalRequestClaimTest < ActiveSupport::TestCase
  StubContext = Struct.new(:roles, :actor_id) do
    def roles_on(_record) = roles
  end
  Req = Struct.new(:submitter_id, :status, :requested_reviewer_ids) do
    def pending? = status == "pending"
  end

  def policy(roles, actor_id, submitter_id, status: "pending", requested: [])
    ApprovalRequestPolicy.new(StubContext.new(roles, actor_id), Req.new(submitter_id, status, requested))
  end

  test "approver(비요청자)는 미배정 리뷰를 claim할 수 있다" do
    assert policy(%w[approver], 2, 1).claim?
  end

  test "owner도 claim할 수 있다 (HARD approve verb 보유)" do
    assert policy(%w[owner], 2, 1).claim?
  end

  test "요청자 본인은 claim 불가 (SoD)" do
    refute policy(%w[approver], 1, 1).claim?
  end

  test "owner도 SoD 예외 없음 — 자기 요청은 claim 불가" do
    refute policy(%w[owner], 1, 1).claim?
  end

  # confirm의 소프트게이트("요청받음=권한")는 claim에 미적용 — approve verb가 없으면 스스로 맡을 수 없다.
  test "approve verb 없는 역할(contributor)은 claim 불가" do
    refute policy(%w[contributor], 2, 1).claim?
  end

  # 이미 지정된 리뷰어는 Segment A(내게 요청된 리뷰)에 있으므로 claim 대상이 아니다.
  test "이미 지정된 리뷰어는 claim 대상 아님" do
    refute policy(%w[approver], 2, 1, requested: [ 2 ]).claim?
  end

  # claim은 미배정 전용: 다른 리뷰어(3)가 이미 지정된 요청은 적격 액터(2)의 직접 POST로도 claim 불가.
  # (UI Segment B의 where.missing 필터를 우회하는 직접 요청의 서버측 백스톱 — 타 리뷰어 배정 요청에 끼어들기 차단.)
  test "다른 리뷰어가 이미 지정된 요청은 claim 불가 (미배정 전용)" do
    refute policy(%w[approver], 2, 1, requested: [ 3 ]).claim?
  end

  test "nil actor(미연결 Account)는 fail-closed" do
    refute policy(%w[approver], nil, 1).claim?
  end

  test "비-pending(reviewed) 요청은 claim 불가" do
    refute policy(%w[approver], 2, 1, status: "reviewed").claim?
  end
end
