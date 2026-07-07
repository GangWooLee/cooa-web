require "test_helper"

# Stage 4 T2 (두 평면 통합): 리뷰어 후보 풀을 product_member(표시 명부) → role_assignment(권한 평면)로
# 재정의한다. 후보 = 버전의 브랜드 루트(팀 단위) 서브트리에 스코프 grant를 가진 계정 ∪ tenant-wide grant
# 보유 계정의 연결 User. 아래는 (1) 신·구 후보 집합의 인원 동일성(무회귀 근거) (2) external_collaborator 제외
# (external뿐인 choi는 자기 스코프 체인에서도 후보 아님 · 다른 역할 병존 시엔 그 역할 근거로 포함)
# (3) 두 평면 분리(미브리지·무권한 표시 멤버 제외)를 고정한다.
class ReviewCandidatesTest < ActiveSupport::TestCase
  setup { Rails.application.load_seed }

  def cv(code, type: "outer_box")
    comp = Product.find_by!(code: code).components.find_by!(component_type: type)
    comp.component_versions.find_by(current: true) || comp.component_versions.first
  end

  def emails(users) = users.map { |u| u.account&.email || u.email }.sort

  # ── CO0001(레티놀 브랜드): 스코프 grant가 없어 후보 = tenant-wide 연결계정 전원 ──
  # 표시 명부(product_member) 4인(kim·song·lee·park)은 전원 tenant-wide → 후보에 포함(무회귀). 팀 밖
  # tenant-wide 신원(유뷰어 viewer·한담당 assignee)도 tenant-wide grant 근거로 후보에 등장(권한 평면).
  test "CO0001 후보 = tenant-wide 연결계정 전원(표시 명부 4인 무회귀 포함)" do
    v = cv("CO0001")
    old_users = v.product.product_members.select(&:user).map(&:user).uniq
    new_users = ReviewCandidates.users_for(v)

    assert_empty old_users.map(&:id) - new_users.map(&:id),
                 "표시 명부 4인은 전원 tenant-wide → 후보에 포함되어야(무회귀)"
    assert_equal %w[han@cooa.dev kim@cooa.dev lee@cooa.dev park@cooa.dev song@cooa.dev yu@cooa.dev], emails(new_users)
  end

  # ── 제출자 제외 ──
  test "exclude_user_id(제출자/뷰어)는 후보에서 제외" do
    v = cv("CO0001")
    kim = User.find_by!(email: "kim@cooa.dev")
    refute_includes ReviewCandidates.users_for(v, exclude_user_id: kim.id).map(&:id), kim.id
  end

  # ── external_collaborator 제외: choi(external뿐 @ CO0200)는 자기 스코프 체인에서도 후보 아님 ──
  # REF 시나리오 ③ — external은 업로드·피드백만(approve/reject·리뷰 확인 표면 없음). 후보 지정이 열리면
  # 지정=소프트그랜트로 confirm까지 우회되므로, 자기 스코프(CO0200) 체인에서도 후보에서 뺀다.
  test "choi(external뿐)는 CO0200 체인에서도 후보 아님 — 규제 검토 확인 무결성" do
    choi = User.find_by!(email: "choi@partner.example")

    co0200_ids = ReviewCandidates.users_for(cv("CO0200")).map(&:id)
    refute_includes co0200_ids, choi.id, "external_collaborator뿐인 계정은 자기 스코프 체인에서도 후보 아님"

    co0001_ids = ReviewCandidates.users_for(cv("CO0001")).map(&:id)
    refute_includes co0001_ids, choi.id, "타 브랜드(레티놀)엔 스코프도 없음 → 당연히 후보 아님"
  end

  # ── external + 다른 역할 병존: external뿐일 때만 제외 — 다른 역할 근거로는 후보 포함 ──
  test "external에 비-external 역할이 병존하면 그 역할 근거로 후보에 포함" do
    choi_acc = Account.find_by!(email: "choi@partner.example")
    # 시드 불변 — 테스트 내에서만 CO0200 체인에 contributor grant를 추가(external 외 역할 병존).
    RoleAssignment.create!(account: choi_acc, tenant_id: choi_acc.tenant_id, role_key: "contributor",
                           scope_type: "product", scope_product_id: Product.find_by!(code: "CO0200").id)
    ids = ReviewCandidates.users_for(cv("CO0200")).map(&:id)
    assert_includes ids, choi_acc.user_id, "external+contributor 병존 → contributor 근거로 후보"
  end

  # ── 스코프 admin(정브랜 @ 비타민C)도 자기 브랜드 버전의 후보로 등장 ──
  test "정브랜(brand_admin @ 비타민C 루트)은 CO0100 버전 후보에 포함" do
    jung = User.find_by!(email: "jung@cooa.dev")
    assert_includes ReviewCandidates.users_for(cv("CO0100")).map(&:id), jung.id
  end

  # ── 두 평면 분리: 무권한 표시 멤버(product_member지만 grant 없음)는 후보에서 제외(의도된 강화) ──
  test "grant 없는 표시-전용 product_member는 후보가 아니다(평면 분리)" do
    v = cv("CO0001")
    ghost = User.create!(name: "표시전용", role: "designer", email: "ghost@display.only", avatar_color: "#999999")
    Account.create!(tenant_id: TenantConfig::DEMO_TENANT_ID, user: ghost, email: ghost.email, status: "active")
    v.product.product_members.create!(user: ghost, role: "마케팅") # 표시 명부엔 추가, grant는 없음

    refute_includes ReviewCandidates.users_for(v).map(&:id), ghost.id,
                    "role_assignment 없는 표시-전용 멤버는 리뷰 후보가 아니어야 함"
  end

  # ── 미브리지(연결 User 없는 계정)는 후보에서 빠진다 ──
  test "user_id 없는(미브리지) 계정의 grant는 후보에 연결 User가 없어 제외" do
    v = cv("CO0001")
    bare = Account.create!(tenant_id: TenantConfig::DEMO_TENANT_ID, email: "bare@nobridge.dev", status: "active")
    RoleAssignment.create!(account: bare, tenant_id: TenantConfig::DEMO_TENANT_ID, role_key: "ra_reviewer", scope_type: "tenant")

    users = ReviewCandidates.users_for(v)
    assert users.all?(&:present?), "후보는 연결 User만 — nil 없음"
    # bare 계정엔 연결 User가 없으므로 후보 수는 tenant-wide 연결계정 수 그대로(kim·song·lee·park·yu·han = 6).
    assert_equal 6, users.size
  end

  test "user_ids_for는 후보 User id 배열(화이트리스트 소스)" do
    v = cv("CO0200")
    assert_equal ReviewCandidates.users_for(v).map(&:id).sort, ReviewCandidates.user_ids_for(v).sort
  end
end
