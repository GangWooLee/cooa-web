require "test_helper"

# Stage 4 T3 (시나리오 ④ — 브랜드-스코프 관리): 정브랜(brand_admin @ 비타민C 브랜드 루트)은 그 브랜드의
# 팀 admin(scoped sub-admin)이다. scoped grant는 조직 레코드 평가에 안 잡히므로(AdminScope 트랩) 인가를
# 2단으로 재구성했다. 아래는 (a) 로스터 경계 (b) 초대 발급 매트릭스 (c) grant 발급/회수 매트릭스
# (d) external 다중 브랜드 가시성 (e) tenant-wide admin 무회귀 (f) 일반 화면 스코프 격리를 서버측에서 고정.
class BrandAdminScopeTest < ActionDispatch::IntegrationTest
  setup do
    @jung  = Account.find_by!(email: "jung@cooa.dev")            # brand_admin @ 비타민C 루트(scoped)
    @kim   = Account.find_by!(email: "kim@cooa.dev")             # owner + brand_admin (tenant-wide) = :all
    @choi  = Account.find_by!(email: "choi@partner.example")     # external @ CO0200(시카) — 타 브랜드
    @vitc  = Product.find_by!(name: "비타민C 브라이트닝 앰플")     # 정브랜의 브랜드 루트
    @co0100 = Product.find_by!(code: "CO0100")                   # 비타민C › 중국 (정브랜 브랜드 서브트리)
    @co0200 = Product.find_by!(code: "CO0200")                   # 시카 › 미국 (타 브랜드)
  end

  # ── (a) 로스터 경계: CO0100 체인 인원만 · tenant-wide 계정 미표시 · 타 브랜드 external 미표시 ──
  test "(a) scoped admin 로스터 = 자기 브랜드 스코프 인원만" do
    sign_in_as(@jung)
    get members_path
    assert_response :success
    body = response.body
    assert_match "정브랜", body, "자기 브랜드(비타민C)의 scoped 멤버(자신)는 보임"
    assert_no_match "김쿠아", body, "tenant-wide 계정(kim)은 scoped admin 로스터에 미표시"
    assert_no_match "이쿠아", body, "tenant-wide 계정(lee)은 미표시"
    assert_no_match "최디자", body, "타 브랜드(시카) external은 미표시"
    # 사이드바 멤버 링크가 scoped admin에게도 노출(can_view_members? — AdminScope 트랩 우회)
    assert_match "멤버", body
  end

  # ── (b) 초대 발급 매트릭스: 자기 브랜드 O · 타 브랜드 403 · tenant-wide 403 ──
  test "(b) scoped admin 초대: 자기 브랜드 성공 · 타 브랜드/전체조직 403·미생성" do
    sign_in_as(@jung)

    assert_difference "Invitation.count", 1 do
      post invitations_path, params: { email: "brand-team@vitc.dev", role_key: "external_collaborator", scope_product_id: @co0100.id }
    end
    assert_equal @co0100.id, Invitation.find_by!(email: "brand-team@vitc.dev").scope_product_id

    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "cross@sica.dev", role_key: "external_collaborator", scope_product_id: @co0200.id }
    end
    assert_response :forbidden

    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "org-wide@x.dev", role_key: "contributor" } # 스코프 없음 = tenant-wide
    end
    assert_response :forbidden
  end

  # ── (c) grant 발급/회수 매트릭스: 자기 브랜드 O · 타 브랜드 발급 403 · 타 브랜드 회수 403 ──
  test "(c) scoped admin grant 발급/회수: 자기 브랜드만" do
    sign_in_as(@jung)

    # 발급: 자기 브랜드(CO0100) 성공
    assert_difference "RoleAssignment.count", 1 do
      post role_assignments_path, params: { account_id: @choi.id, role_key: "external_collaborator", scope_product_id: @co0100.id }
    end
    granted = @choi.role_assignments.find_by!(scope_product_id: @co0100.id)

    # 발급: 타 브랜드(CO0200) 403·미생성
    assert_no_difference "RoleAssignment.count" do
      post role_assignments_path, params: { account_id: @kim.id, role_key: "external_collaborator", scope_product_id: @co0200.id }
    end
    assert_response :forbidden

    # 회수: 자기 브랜드 grant(방금 발급한 CO0100)는 성공
    assert_difference "RoleAssignment.count", -1 do
      delete role_assignment_path(granted)
    end

    # 회수: 타 브랜드 grant(시드 choi@CO0200)는 403·잔존
    other = @choi.role_assignments.find_by!(scope_product_id: @co0200.id)
    assert_no_difference "RoleAssignment.count" do
      delete role_assignment_path(other)
    end
    assert_response :forbidden
    assert RoleAssignment.exists?(other.id)
  end

  # ── (d) external은 부여된 모든 브랜드의 admin에 가시(체인 grant 기준) ──
  test "(d) external(choi)을 비타민C에도 grant → 정브랜·시카admin 두 admin 모두에 가시" do
    # choi를 CO0100(비타민C)에도 grant → 이제 시카(seed) + 비타민C 두 브랜드에 스코프.
    RoleAssignment.create!(account: @choi, tenant_id: @choi.tenant_id, role_key: "external_collaborator",
                           scope_type: "product", scope_product_id: @co0100.id)
    # 시카 브랜드 admin(정시카)을 만든다.
    sica = Product.find_by!(name: "시카 수딩 크림")
    sica_admin_user = User.create!(name: "정시카", role: "pm", email: "sica-admin@cooa.dev", avatar_color: "#a86e3f")
    sica_admin = Account.create!(tenant_id: @choi.tenant_id, user: sica_admin_user, email: sica_admin_user.email, status: "active")
    RoleAssignment.create!(account: sica_admin, tenant_id: @choi.tenant_id, role_key: "brand_admin",
                           scope_type: "product", scope_product_id: sica.id)

    sign_in_as(@jung) # 비타민C admin
    get members_path
    assert_match "최디자", response.body, "비타민C에 grant된 external은 비타민C admin에 가시"

    sign_in_as(sica_admin) # 시카 admin
    get members_path
    assert_match "최디자", response.body, "시카에 grant된 external은 시카 admin에도 가시"
  end

  # ── (e) tenant-wide admin(kim) 전 기능 무회귀 ──
  test "(e) tenant-wide admin은 전체 로스터 + tenant-wide 초대 발급(무회귀)" do
    sign_in_as(@kim)
    get members_path
    assert_response :success
    body = response.body
    %w[김쿠아 송쿠아 이쿠아 박쿠아 최디자 정브랜].each { |n| assert_match n, body, "tenant-wide admin은 전 인원 로스터" }

    assert_difference "Invitation.count", 1 do
      post invitations_path, params: { email: "org-invite@x.dev", role_key: "contributor" } # tenant-wide 발급 허용
    end
    assert_nil Invitation.find_by!(email: "org-invite@x.dev").scope_product_id
  end

  # ── (f) 정브랜의 일반 화면은 tenant-wide 역할 없음 → 자기 브랜드 스코프만(기존 Scope 동작) ──
  test "(f) scoped admin 대시보드/트리는 자기 브랜드만 · 타 브랜드 부재" do
    sign_in_as(@jung)
    get root_path
    assert_response :success
    body = response.body
    assert_match "비타민C 브라이트닝 앰플", body
    assert_match "CO0100", body
    assert_no_match "레티놀 3% 세럼", body
    assert_no_match "시카 수딩 크림", body
  end

  # ── scoped 로스터 렌더 N+1 게이트(스코프 배지 프리로드) ──
  test "scoped admin 로스터 렌더는 N+1 없음" do
    RoleAssignment.create!(account: @choi, tenant_id: @choi.tenant_id, role_key: "external_collaborator",
                           scope_type: "product", scope_product_id: @co0100.id) # 로스터 2인 이상으로 게이트 활성
    sign_in_as(@jung)
    assert_no_n_plus_one { get members_path }
    assert_response :success
  end
end
