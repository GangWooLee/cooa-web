require "test_helper"

# Stage 3 (D4/D5, 시나리오 ③ end-to-end): an OUTSIDE agency is invited to ONE product only, accepts via
# Google, and lands with a PRODUCT-scoped grant — sees just that product (no ancestor-brand leak), is blocked
# elsewhere. Then an admin adds a SECOND product via direct grant (visible with NO re-login), then revokes it
# (back to one). Two live sessions (open_session) prove the grant takes effect on the agency's existing
# session without re-authentication. brand_admin(song) issues; contributor(park) is refused; a repeat grant
# is idempotent.
class ScopedInviteTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @song   = Account.find_by!(email: "song@cooa.dev")            # brand_admin → manage_members
    @park   = Account.find_by!(email: "park@cooa.dev")            # contributor → no manage_members
    @co0100 = Product.find_by!(code: "CO0100")                    # 비타민C…앰플 › 중국
    @co0200 = Product.find_by!(code: "CO0200")                    # 시카 수딩 크림 › 미국
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def sign_in(sess, account) = sess.post(session_path, params: { account_id: account.id })

  # A fresh (logged-out) session accepts the invite: landing seeds session[:invite_token], the Google
  # callback's 3rd fallback runs InvitationAcceptance.
  def google_accept(sess, raw, uid:, email:, name: "에이전시")
    sess.get invite_path(raw)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: { email: email, name: name },
      extra: { raw_info: { email_verified: true } }
    )
    sess.get "/auth/google_oauth2/callback"
  end

  # Issue a scoped invite through the real controller and recover the one-shot raw token from the rendered
  # members page (digest-only storage → the link only exists in the flash-rendered response).
  def issue_scoped_invite(admin, email:, product:)
    admin.post invitations_path, params: { email: email, role_key: "external_collaborator", scope_product_id: product.id }
    admin.follow_redirect!
    admin.response.body[%r{/invite/([A-Za-z0-9_\-]+)}, 1]
  end

  test "시나리오 ③: 제품-한정 초대 → 격리 → 직접 grant로 2번째 제품(재로그인 없이) → 회수" do
    agency = open_session
    admin  = open_session
    sign_in(admin, @song)

    # 1) brand_admin이 CO0100 스코프 초대 발급 — 초대·감사에 scope 반영
    raw = issue_scoped_invite(admin, email: "agency@partner.dev", product: @co0100)
    inv = Invitation.find_by!(email: "agency@partner.dev")
    assert_equal [ "product", @co0100.id ], [ inv.scope_type, inv.scope_product_id ]
    cre = AuditLog.where(action: "invitation.create").order(:ts).last
    assert_equal [ "product", @co0100.id ], [ cre.after["scope_type"], cre.after["scope_product_id"] ]

    # 2) 외부인 수락 → 제품-스코프 grant(tenant-wide 아님)
    assert_difference [ "Account.count", "RoleAssignment.count" ], 1 do
      google_accept(agency, raw, uid: "g-agency", email: "agency@partner.dev")
    end
    agency.assert_redirected_to root_path
    agency_acc = Account.find_by!(email: "agency@partner.dev")
    ra = agency_acc.role_assignments.sole
    assert_equal [ "external_collaborator", "product", @co0100.id ], [ ra.role_key, ra.scope_type, ra.scope_product_id ]
    refute ra.tenant_wide?, "제품 초대가 tenant-wide grant를 만들면 전 테넌트 유출"

    # 3) CO0100만 가시 · 조상 브랜드명 무유출 · 타 제품 차단
    agency.get root_path
    agency.assert_response :success
    assert_match "CO0100", agency.response.body
    assert_no_match "비타민C 브라이트닝 앰플", agency.response.body # 비가시 조상 브랜드 루트
    assert_no_match "레티놀 3% 세럼", agency.response.body
    assert_no_match "시카 수딩 크림", agency.response.body

    agency.get product_path(@co0100)
    agency.assert_response :success
    assert_no_match "비타민C 브라이트닝 앰플", agency.response.body # 드로어 경로에도 무유출

    agency.get product_path(@co0200)
    agency.assert_redirected_to root_path # 타 제품 진입 차단

    # 4) admin이 직접 grant로 CO0200 추가 → agency는 재로그인 없이 즉시 두 제품 가시
    assert_difference "RoleAssignment.count", 1 do
      admin.post role_assignments_path, params: {
        account_id: agency_acc.id, role_key: "external_collaborator", scope_product_id: @co0200.id
      }
    end
    admin.assert_redirected_to members_path
    grant = AuditLog.where(action: "role_assignment.grant").order(:ts).last
    assert_equal [ agency_acc.id, "external_collaborator", @co0200.id ],
                 [ grant.after["account_id"], grant.after["role_key"], grant.after["scope_product_id"] ]

    agency.get product_path(@co0200) # 재로그인 없이
    agency.assert_response :success
    agency.get root_path
    assert_match "CO0100", agency.response.body
    assert_match "CO0200", agency.response.body

    # 5) admin이 CO0200 grant 회수 → 다시 CO0100만
    co0200_ra = agency_acc.role_assignments.find_by!(scope_product_id: @co0200.id)
    assert_difference "RoleAssignment.count", -1 do
      admin.delete role_assignment_path(co0200_ra)
    end
    assert AuditLog.where(action: "role_assignment.revoke").exists?
    agency.get product_path(@co0200)
    agency.assert_redirected_to root_path
    agency.get root_path
    assert_no_match "CO0200", agency.response.body
  end

  test "직접 grant 발급은 manage_members 전용 — contributor(park)는 403·미생성" do
    target = Account.find_by!(email: "choi@partner.example")
    sign_in_as(@park)
    assert_no_difference "RoleAssignment.count" do
      post role_assignments_path, params: { account_id: target.id, role_key: "external_collaborator", scope_product_id: @co0100.id }
    end
    assert_response :forbidden
  end

  test "동일 스코프 grant 재부여는 멱등(RecordNotUnique → 안내·미중복)" do
    target = Account.find_by!(email: "choi@partner.example") # 시드에서 CO0200 보유 → CO0100은 신규
    sign_in_as(@song)
    assert_difference "RoleAssignment.count", 1 do
      post role_assignments_path, params: { account_id: target.id, role_key: "external_collaborator", scope_product_id: @co0100.id }
    end
    assert_no_difference "RoleAssignment.count" do
      post role_assignments_path, params: { account_id: target.id, role_key: "external_collaborator", scope_product_id: @co0100.id }
    end
    assert_redirected_to members_path
    assert_equal "이미 부여된 권한입니다.", flash[:alert]
    # flash가 실제로 렌더되는지(레이아웃 flash 블록) — 값 단언을 본문 단언으로 승격.
    follow_redirect!
    assert_match "이미 부여된 권한입니다.", response.body
  end

  test "멤버 로스터 렌더는 N+1을 내지 않음(스코프 배지·제품 select 프리로드)" do
    # 로드-베어링 setup: 서로 다른 제품에 스코프 grant를 가진 계정이 2개 이상이어야 로스터 렌더가 scope_product
    # 이름을 계정당 1회씩 N회 조회 → members_controller의 role_assignments:[:scope_product,:scope_component]
    # 프리로드가 없으면 Prosopite가 N+1로 raise한다. (시드는 choi@CO0200 하나뿐이라 조회 1회 → 프리로드를 빼도
    # green이었음 — 리뷰어 실증. 아래 2번째 grant(다른 제품 CO0100)가 게이트를 실제로 물게 한다.
    # 프리로드 임시 제거 실험 시 이 테스트가 RED임을 확인함.)
    second = Account.create!(tenant_id: @song.tenant_id, email: "scoped2@partner.dev", status: "active")
    RoleAssignment.create!(account: second, tenant_id: @song.tenant_id, role_key: "external_collaborator",
                           scope_type: "product", scope_product_id: @co0100.id)
    sign_in_as(@song) # brand_admin → 전체 로스터 + 스코프 배지(choi@CO0200 + scoped2@CO0100) + 인라인 grant 폼
    assert_no_n_plus_one { get members_path }
    assert_response :success
  end

  test "destroy는 스코프 grant 전용 — tenant-wide grant 회수 시도는 404·잔존(신규 HTTP 능력 차단)" do
    lee = Account.find_by!(email: "lee@cooa.dev")               # ra_reviewer+approver, 둘 다 tenant-wide
    tw  = lee.role_assignments.find_by!(role_key: "approver", scope_type: "tenant")
    sign_in_as(@song)                                           # manage_members 보유
    assert_no_difference "RoleAssignment.count" do
      delete role_assignment_path(tw)
    end
    assert_response :not_found
    assert RoleAssignment.exists?(tw.id), "tenant-wide grant는 이 경로로 회수될 수 없다"
  end

  test "직접 grant는 owner 역할을 서버측에서 거부(권한 상승 차단)" do
    target = Account.find_by!(email: "choi@partner.example")
    sign_in_as(@song)
    assert_no_difference "RoleAssignment.count" do
      post role_assignments_path, params: { account_id: target.id, role_key: "owner", scope_product_id: @co0100.id }
    end
  end
end
