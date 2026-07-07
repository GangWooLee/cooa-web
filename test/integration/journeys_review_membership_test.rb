require "test_helper"

# W2 페르소나 저니 — 리뷰 라운드트립 stale + 스코프 멤버십 온보딩. 상태가 이어지는 체인만.
#   J6 contributor(park) stale 왕복: 업로드→미지정 요청→lee claim→콘텐츠 변경→stale로 확인 차단(StaleReviewedTuple).
#      (approval_workflow의 stale은 직접 지정 요청 — 여기는 claim 경로 + contributor 업로드 제네시스를 엮음.)
#   J2 scoped admin(jung) workspace_memberships 통합 엔드포인트: 자기 작업실 초대 발급 O · 역할 화이트리스트 클램프 ·
#      관할 밖 작업실 위조 거부. (workspace_membership_test는 jung을 실패 케이스로만 — 여기는 발급 성공 분기 + 클램프.)
#   J7 초대 수락 신규 사용자 풀 저니: jung 발급 작업실 초대 → Google 수락 → workspace 스코프 grant → 자기 작업실만
#      가시 → 스코프 내 첫 업로드. (scoped_invite는 song 발급·제품 스코프·수락자 미업로드 — 여기는 jung·작업실·첫 작업.)
class JourneysReviewMembershipTest < ActionDispatch::IntegrationTest
  setup { OmniAuth.config.test_mode = true }

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def fresh_artwork = fixture_file_upload("box.jpg", "image/jpeg")

  def google_login(uid:, email:, verified: true, name: "신규 협력자")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: { email: email, name: name },
      extra: { raw_info: { email_verified: verified } }
    )
    get "/auth/google_oauth2/callback"
  end

  # ── J6: contributor stale 왕복(업로드→미지정→claim→콘텐츠 변경→stale 차단) ──
  test "J6 park stale: 버전 업로드→미지정 요청→lee claim→콘텐츠 변경→검토 확인 stale 차단(pending·deny 감사)" do
    park   = Account.find_by!(email: "park@cooa.dev")
    lee    = Account.find_by!(email: "lee@cooa.dev")
    comp   = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")

    # 1) park(contributor) 새 버전 업로드
    sign_in_as(park)
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "협력 시안", artwork: fresh_artwork } }
    end
    v = comp.component_versions.order(:version_number).last

    # 2) 리뷰 대상 콘텐츠(라벨) 심기 — stale 감지가 label_texts 스냅샷을 물게(요청 전 존재해야 스냅샷 포함).
    v.label_texts.create!(text_type: "label", content: "ORIGINAL 30ml", language: "en", country: "JP")

    # 3) park 미지정 리뷰 요청 → pending·미배정
    assert_difference "ApprovalRequest.count", 1 do
      post approval_requests_path, params: { component_version_id: v.id }
    end
    req = ApprovalRequest.find_by!(component_version_id: v.id)
    assert_empty req.requested_reviewer_ids, "리뷰어 미지정 제출"

    # 4) lee(적격 approver) claim → Segment A로 이동
    sign_in_as(lee)
    assert_difference -> { req.approval_request_reviewers.count }, 1 do
      post claim_approval_request_path(req)
    end
    assert_includes req.reload.requested_reviewer_ids, lee.user_id

    # 5) 요청 후 콘텐츠 변경 → 스냅샷과 발산
    v.label_texts.first.update!(content: "CHANGED AFTER REQUEST")

    # 6) lee 검토 확인 → StaleReviewedTuple → pending 유지 + stale deny 감사
    post confirm_approval_request_path(req)
    assert_response :see_other
    assert_equal "pending", req.reload.status, "stale면 확인되면 안 됨"
    assert AuditLog.where(outcome: "deny", denial_reason: "stale_reviewed_tuple", resource_id: req.id).exists?,
           "stale 차단은 deny 감사(stale_reviewed_tuple)로 기록"
  end

  # ── J2: scoped admin(jung) workspace_memberships 통합 엔드포인트 ─────────────
  test "J2 jung(비타민C scoped): 자기 작업실 초대 발급 O · 역할 클램프 · 관할 밖(시카) 위조 403" do
    jung    = Account.find_by!(email: "jung@cooa.dev")
    vitc_ws = Product.find_by!(name: "비타민C 브라이트닝 앰플").workspace
    cica_ws = Product.find_by!(name: "시카 수딩 크림").workspace
    sign_in_as(jung)

    # (a) 자기 작업실 미지 이메일 → 초대 발급(workspace 스코프) · grant 미생성 · 링크 노출 · 온 자리 복귀
    assert_difference "Invitation.count", 1 do
      assert_no_difference "RoleAssignment.count" do
        post workspace_memberships_path, params: {
          email: "brand-hire@vitc.dev", role_key: "external_collaborator",
          scope_workspace_id: vitc_ws.id, return_to_workspace: vitc_ws.id
        }
      end
    end
    assert_redirected_to workspace_path(vitc_ws)
    inv = Invitation.find_by!(email: "brand-hire@vitc.dev")
    assert_equal [ "workspace", vitc_ws.id ], [ inv.scope_type, inv.scope_workspace_id ], "발급 초대는 이 작업실 스코프(전사 아님)"
    assert flash[:invite_link].present?, "1회용 초대 링크 노출"

    # (b) 전사 전용 역할(approver) 위조 → 팀 4종 화이트리스트 클램프 · 미생성
    assert_no_difference [ "Invitation.count", "RoleAssignment.count" ] do
      post workspace_memberships_path, params: {
        email: "forge@vitc.dev", role_key: "approver",
        scope_workspace_id: vitc_ws.id, return_to_workspace: vitc_ws.id
      }
    end
    assert_match "추가할 수 없", flash[:alert].to_s

    # (c) 관할 밖 작업실(시카)로 위조 발급 → 403 · 미생성(scope_workspace_id가 경계)
    assert_no_difference [ "Invitation.count", "RoleAssignment.count" ] do
      post workspace_memberships_path, params: {
        email: "cross@sica.dev", role_key: "external_collaborator", scope_workspace_id: cica_ws.id
      }
    end
    assert_response :forbidden
  end

  # ── J7: 초대 수락 신규 사용자 풀 저니(jung 발급 → 수락 → 가시성 → 첫 업로드) ─
  test "J7 신규 사용자: jung 발급 작업실 초대 → Google 수락 → workspace grant → 자기 작업실만 가시 → 첫 업로드" do
    jung    = Account.find_by!(email: "jung@cooa.dev")
    vitc_ws = Product.find_by!(name: "비타민C 브라이트닝 앰플").workspace
    co0100  = Product.find_by!(code: "CO0100") # 비타민C › 중국(리프, 이 작업실 소속)

    # 1) jung(scoped admin)이 자기 작업실 스코프 초대 발급(invitations 컨트롤러 — scoped 인가 통과 증명)
    sign_in_as(jung)
    post invitations_path, params: { email: "newhire@vitc.dev", role_key: "external_collaborator", scope_workspace_id: vitc_ws.id }
    assert_redirected_to members_path
    raw = flash[:invite_link].to_s[%r{/invite/([A-Za-z0-9_\-]+)}, 1]
    assert raw.present?, "발급 응답에서 1회용 raw 토큰 확보"

    # 2) 로그아웃 후 신규 사용자가 Google로 수락 → User+Account+RoleAssignment 각 1 · workspace 스코프 grant
    sign_out
    get invite_path(raw)
    assert_response :success
    assert_difference [ "Account.count", "User.count", "RoleAssignment.count" ], 1 do
      google_login(uid: "g-newhire", email: "newhire@vitc.dev")
    end
    assert_redirected_to root_path
    acc = Account.find_by!(email: "newhire@vitc.dev")
    ra  = acc.role_assignments.sole
    assert_equal [ "external_collaborator", "workspace", vitc_ws.id ], [ ra.role_key, ra.scope_type, ra.scope_workspace_id ]

    # 3) 가시성: 자기 작업실(비타민C)만 · 타 브랜드 부재(수락자 세션 그대로)
    get root_path
    assert_response :success
    assert_match "비타민C 브라이트닝 앰플", response.body
    assert_no_match "레티놀 3% 세럼", response.body
    assert_no_match "시카 수딩 크림", response.body

    # 4) 첫 작업: 스코프 내 제품(CO0100)에 버전 업로드(external upload_version — 재로그인 없이 즉시)
    comp = co0100.components.find_by!(component_type: "outer_box")
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "신규 협력자 시안", artwork: fresh_artwork } }
    end
  end
end
