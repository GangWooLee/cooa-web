require "test_helper"

# Phase 3 초대-게이트 온보딩 매트릭스 — OmniAuth test_mode(라이브 IdP 불필요)로 콜백 경로 직접 구동.
# 초대 랜딩(GET /invite/:token)이 세션에 토큰을 심고, Google 콜백의 3번째 폴백이 원자 수락.
# 신원 페르소나: 김=owner+brand_admin, 송=brand_admin, 이=ra_reviewer+approver, 박=contributor.
class InvitationSignupTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @kim = Account.find_by!(email: "kim@cooa.dev")
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def invite!(email: "new@partner.dev", role_key: "contributor")
    Invitation.generate!(email: email, role_key: role_key, invited_by_account_id: @kim.id)
  end

  def google_login(uid:, email:, verified: true, name: "새 팀원")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid,
      info: { email: email, name: name }, extra: { raw_info: { email_verified: verified } }
    )
    get "/auth/google_oauth2/callback"
  end

  def visit_invite_then_login(raw, uid:, email:, verified: true)
    sign_out
    get invite_path(raw)      # 랜딩 → session[:invite_token]
    assert_response :success
    google_login(uid: uid, email: email, verified: verified)
  end

  test "정상 수락: 랜딩→Google 로그인→3-레코드 생성·바인딩·accepted·audit·세션 확립" do
    inv, raw = invite!
    assert_difference [ "User.count", "Account.count", "RoleAssignment.count" ], 1 do
      visit_invite_then_login(raw, uid: "g-new-sub", email: "new@partner.dev")
    end
    assert_redirected_to root_path
    acc = Account.find_by!(email: "new@partner.dev")
    assert_equal [ "google_oauth2", "g-new-sub" ], [ acc.idp_provider, acc.idp_subject ]
    assert_equal "contributor", acc.role_assignments.sole.role_key
    assert_equal @kim.id, acc.role_assignments.sole.granted_by
    assert inv.reload.accepted_at.present?
    assert_equal acc.id, inv.accepted_account_id
    accept_audit = AuditLog.where(action: "invitation.accept", outcome: "allow").order(:ts).last
    assert accept_audit, "수락 감사 행이 기록되어야"
    assert_equal inv.id, accept_audit.after["invitation_id"], "uuid는 after 페이로드로 식별(resource_id=bigint 공간)"
    follow_redirect!
    assert_response :success, "수락 직후 세션이 확립되어 대시보드 접근 가능해야"
  end

  test "티켓 없이 미지 verified Google 이메일 → 셀프서브 온보딩(T3: 미초대 신규 가입)" do
    sign_out
    google_login(uid: "g-x", email: "newcomer@startup.test")
    assert_redirected_to new_onboarding_path, "미초대 verified 신원은 이제 거부 대신 자기 조직 온보딩으로(T3)"
    assert_nil Account.find_by(email: "newcomer@startup.test"), "온보딩 화면 진입 시점엔 계정 미생성(POST에서 원자 생성)"
  end

  test "unverified 이메일 → reject·초대 미소비" do
    inv, raw = invite!
    visit_invite_then_login(raw, uid: "g-unv", email: "new@partner.dev", verified: false)
    assert_redirected_to new_session_path
    assert inv.reload.pending?, "초대는 소비되면 안 됨"
    assert_nil Account.find_by(email: "new@partner.dev")
  end

  test "이메일 불일치(토큰 탈취 시나리오) → reject·초대 미소비" do
    inv, raw = invite!(email: "victim@partner.dev")
    visit_invite_then_login(raw, uid: "g-thief", email: "thief@evil.test")
    assert_redirected_to new_session_path
    assert inv.reload.pending?
    assert_nil Account.find_by(email: "thief@evil.test")
  end

  test "scoped 초대도 동일 게이트: 이메일 불일치(토큰 탈취) → reject·미소비·grant 미생성" do
    co0100 = Product.find_by!(code: "CO0100")
    inv, raw = Invitation.generate!(email: "victim@partner.dev", role_key: "external_collaborator",
                                    invited_by_account_id: @kim.id,
                                    scope_type: "product", scope_product_id: co0100.id)
    visit_invite_then_login(raw, uid: "g-thief-scoped", email: "thief@evil.test")
    assert_redirected_to new_session_path
    assert inv.reload.pending?, "스코프 초대도 이메일 불일치면 소비되면 안 됨(동일 게이트)"
    assert_nil Account.find_by(email: "thief@evil.test")
  end

  # 죽은 티켓(만료·회수·선클레임)은 랜딩이 무효 판정 → session[:invite_token] 미스태시. 콜백엔 초대 컨텍스트가
  # 없으니 검증 google 신원은 "미초대"와 구별 불가 → 셀프서브 온보딩으로 분기(T3). 핵심 불변식은 유지된다:
  # 죽은 티켓으로 **초대 조직에 편입되지 않는다**(그 조직에 계정 미생성·티켓 미소비). 온보딩은 별도 새 조직이다.
  test "만료 티켓 → 랜딩은 무효 안내 + 콜백은 셀프서브 온보딩(초대 조직 미가입·미소비)" do
    inv, raw = invite!
    inv.update!(expires_at: 1.minute.ago)
    sign_out
    get invite_path(raw)
    assert_response :success
    assert_match "유효하지 않은 초대", response.body # 만료 티켓은 랜딩부터 무효(토큰 미스태시)
    google_login(uid: "g-late", email: "new@partner.dev")
    assert_redirected_to new_onboarding_path
    assert_nil inv.reload.accepted_account_id, "만료 티켓은 소비되지 않는다(초대 조직 편입 아님)"
  end

  test "회수된 티켓 → 셀프서브 온보딩(초대 조직 미가입·미소비)" do
    inv, raw = invite!
    inv.revoke!
    visit_invite_then_login(raw, uid: "g-revoked", email: "new@partner.dev")
    assert_redirected_to new_onboarding_path
    assert_nil Account.find_by(email: "new@partner.dev"), "온보딩 진입 시점엔 계정 미생성(초대 조직 편입 아님)"
    assert_nil inv.reload.accepted_account_id, "회수 티켓은 소비되지 않는다"
  end

  test "동시 수락 레이스: 선클레임되면 그 티켓은 무효 → 패자는 초대 조직 미가입(자기 조직 온보딩)" do
    inv, raw = invite!
    assert inv.claim!, "선클레임(승자 시뮬)"
    assert_no_difference [ "User.count", "Account.count" ] do # 콜백은 온보딩 화면으로만 — 레코드 미생성(POST에서 생성)
      visit_invite_then_login(raw, uid: "g-loser", email: "new@partner.dev")
    end
    assert_redirected_to new_onboarding_path # 이미 클레임된 티켓은 미스태시 → 패자는 초대 조직에 못 들어간다
  end

  test "수락자 재로그인은 재방문 매칭으로 성공(티켓 불필요)" do
    _inv, raw = invite!
    visit_invite_then_login(raw, uid: "g-return", email: "new@partner.dev")
    delete session_path
    google_login(uid: "g-return", email: "new@partner.dev") # 티켓 없이
    assert_redirected_to root_path
  end

  test "초대 후 pre-provisioned 계정이 생긴 경우 → bind 승리 + 유령 pending 소비" do
    # 순서가 핵심: 초대가 먼저(그때는 비멤버라 생성 가능), 이후 운영자가 계정을 직접 프로비저닝한 상황.
    inv, raw = invite!(email: "ops@partner.dev", role_key: "contributor")
    ops_user = User.create!(name: "옵스", email: "ops@partner.dev", role: "pm", avatar_color: "#6b7280")
    Account.create!(tenant_id: TenantConfig::DEMO_TENANT_ID, user: ops_user,
                    email: "ops@partner.dev", status: "active") # 미바인딩(idp_subject nil)
    assert_no_difference [ "Account.count" ] do # 신규 생성이 아니라 기존 계정 바인딩이어야
      visit_invite_then_login(raw, uid: "g-ops", email: "ops@partner.dev")
    end
    assert_redirected_to root_path
    ops = Account.find_by!(email: "ops@partner.dev")
    assert_equal "google_oauth2", ops.idp_provider, "bind 경로로 바인딩"
    refute inv.reload.pending?, "유령 pending이 남아 재초대를 막으면 안 됨"
    assert_equal ops.id, inv.accepted_account_id
  end

  # ── 멤버 페이지 권한 매트릭스 ──

  test "멤버 페이지: contributor(박)는 거부, approver(이)는 열람만, brand_admin(송)은 초대 생성·회수 + audit" do
    sign_in_as(Account.find_by!(email: "park@cooa.dev")) # contributor — list_tenant_accounts 없음
    get members_path
    assert_redirected_to root_path # deny 규약: GET+HTML은 303 루트(알림), 비-GET은 403

    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))  # approver/ra_reviewer — 열람 가능
    get members_path
    assert_response :success
    post invitations_path, params: { email: "x@y.dev", role_key: "viewer" } # manage_members 없음
    assert_response :forbidden

    sign_in_as(Account.find_by!(email: "song@cooa.dev")) # brand_admin — manage_members
    assert_difference "Invitation.count", 1 do
      post invitations_path, params: { email: "teammate@partner.dev", role_key: "contributor" }
    end
    assert_redirected_to members_path
    assert flash[:invite_link].present?, "raw 링크는 생성 응답에서 1회 노출"
    assert AuditLog.where(action: "invitation.create", outcome: "allow").exists?
    inv = Invitation.find_by!(email: "teammate@partner.dev")
    delete invitation_path(inv)
    assert inv.reload.revoked_at.present?
    assert AuditLog.where(action: "invitation.revoke", outcome: "allow").exists?
  end

  test "owner 역할 초대는 거부(권한 상승 차단) + 기존 멤버 이메일 초대 거부" do
    sign_in_as(Account.find_by!(email: "kim@cooa.dev"))
    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "boss@partner.dev", role_key: "owner" }
    end
    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "lee@cooa.dev", role_key: "viewer" } # 이미 멤버
    end
  end
end
