require "test_helper"

# H3 (v1.5 아크 종결 하드닝): 멀티역할·엣지 시나리오. 개별 축은 기존 파일이 부분 커버하나, 아래는 그
# "교차/왕복/네거티브-스윕/회수-즉시성"의 결합을 한 곳에서 게이트한다. 인벤토리(커버됨/신규)는 브리프 참조.
#   1) 왕복 정합    — 배지 == Segment A 카운트 불변식 + confirm 단계까지(review_claim은 claim 델타까지만).
#   2) 멀티역할 kim — owner+brand_admin이 SoD 차단·members 관리·전 트리 가시를 동시 성립(신규: 결합).
#   3) 네거티브     — choi 스코프 계정의 4개 mutation(타 제품 claim·비가시 버전 리뷰요청·초대·grant) 403 스윕.
#   4) 회수 즉시성  — choi의 유일 grant 회수 → 라이브 세션이 다음 요청에서 빈 대시보드 fail-closed(0-grant).
class V15EdgeTest < ActionDispatch::IntegrationTest
  def hero_v5
    Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
           .component_versions.find_by!(version_number: 5)
  end

  # 사이드바 pending_review_count 배지(부재=0) · 인박스 Segment A 헤더 카운트. 둘은 "내가 지정 리뷰어인 pending"
  # 이라는 동일 술어에서 나오므로 항상 같아야 한다(드리프트 게이트).
  def sidebar_badge = css_select("aside#app-sidebar span.bg-cooa").first&.text.to_i
  def segment_a_count = response.body[/내게 요청된 리뷰\s*<span[^>]*>\((\d+)\)/, 1].to_i

  def sign_in(sess, account) = sess.post(session_path, params: { account_id: account.id })

  # ── 1) 왕복 정합: 제출 → claim → confirm 각 단계에서 배지 == Segment A, Segment B 반영 ──
  test "왕복 정합: park 제출 → lee claim → confirm — 각 단계 배지 == Segment A, Segment B 이동" do
    sign_in_as(Account.find_by!(email: "park@cooa.dev")) # contributor
    post approval_requests_path, params: { component_version_id: hero_v5.id } # 리뷰어 미지정
    req = ApprovalRequest.find_by!(component_version_id: hero_v5.id)

    sign_in_as(Account.find_by!(email: "lee@cooa.dev")) # ra_reviewer+approver = 적격

    # ① 제출 직후: CO0001은 미배정 → lee의 Segment B에만. 배지 == Segment A(불변식).
    get reviews_path
    assert_response :success
    assert_equal sidebar_badge, segment_a_count, "배지와 Segment A 카운트는 항상 일치해야 함"
    a1 = segment_a_count
    assert_match "CO0001", response.body      # Segment B(미배정·적격)에 노출
    assert_match "내가 맡기", response.body    # B의 claim 어포던스

    # ② claim → 미배정에서 내 리뷰로 이동, 배지 +1, 불변식 유지, B는 비워짐.
    post claim_approval_request_path(req)
    get reviews_path
    assert_equal sidebar_badge, segment_a_count, "claim 후에도 배지 == Segment A"
    assert_equal a1 + 1, segment_a_count, "claim이 미배정→내 리뷰로 이동(+1)"
    assert_match "맡을 수 있는 미배정 리뷰가 없습니다", response.body

    # ③ confirm → reviewed 종결, pending에서 빠져 배지·A 원복, 불변식 유지.
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status
    get reviews_path
    assert_equal sidebar_badge, segment_a_count, "confirm 후에도 배지 == Segment A"
    assert_equal a1, segment_a_count, "confirm이 pending에서 제거 → 배지·A 원복"
  end

  # ── 2) 멀티역할 kim(owner+brand_admin): SoD 차단 + members 관리 + 전 트리 가시 동시 성립 ──
  test "멀티역할 kim: 자기제출 confirm SoD 차단 · members 관리 능력 · 전 트리 가시가 동시 성립" do
    sign_in_as(Account.find_by!(email: "kim@cooa.dev")) # owner + brand_admin

    # (a) SoD: 본인이 제출한 리뷰는 owner라도 본인이 확인 불가(예외 없음).
    post approval_requests_path, params: { component_version_id: hero_v5.id }
    req = ApprovalRequest.find_by!(component_version_id: hero_v5.id)
    post confirm_approval_request_path(req)
    assert_response :forbidden
    assert_equal "pending", req.reload.status, "SoD로 본인 확인이 차단되어 pending 유지"

    # (b) members 관리 UI 접근 + 실제 manage_members 능력(brand_admin/owner).
    get members_path
    assert_response :success
    assert_difference "Invitation.count", 1 do
      post invitations_path, params: { email: "conj@partner.dev", role_key: "contributor" }
    end

    # (c) tenant-wide → 전 브랜드 트리 가시(무회귀).
    get root_path
    assert_response :success
    assert_match "레티놀 3% 세럼", response.body
    assert_match "비타민C 브라이트닝 앰플", response.body
    assert_match "시카 수딩 크림", response.body
  end

  # ── 3) 네거티브 스윕: choi(external_collaborator @ CO0200)의 4개 mutation 모두 403·미생성 ──
  test "네거티브: choi 스코프 계정의 타제품 claim·비가시 리뷰요청·초대·grant는 전부 403·미생성" do
    choi   = Account.find_by!(email: "choi@partner.example")
    co0001 = Product.find_by!(code: "CO0001")           # choi 비가시(CO0200만 스코프)
    co0200 = Product.find_by!(code: "CO0200")
    invisible_v = co0001.components.first.component_versions.first
    # 타 제품(CO0001)에 미배정 pending 리뷰를 하나 준비(kim 제출) — claim 대상.
    kim = User.find_by!(email: "kim@cooa.dev")
    other_req = ApprovalRequest.submit_for!(hero_v5, submitter_id: kim.id, reviewer_ids: [])

    sign_in_as(choi)

    # 1) 타 제품 approval_request claim → 비적격 403, 리뷰어 미생성.
    assert_no_difference -> { other_req.approval_request_reviewers.count } do
      post claim_approval_request_path(other_req)
    end
    assert_response :forbidden

    # 2) 비가시 버전에 리뷰 요청(create) → 403, 요청 미생성(same-tenant라 find는 되지만 인가 거부).
    assert_no_difference "ApprovalRequest.count" do
      post approval_requests_path, params: { component_version_id: invisible_v.id }
    end
    assert_response :forbidden

    # 3) 초대 발급 → manage_members 없음 403, 미생성.
    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "x@partner.dev", role_key: "contributor" }
    end
    assert_response :forbidden

    # 4) 직접 grant 부여 → manage_members 없음 403, 미생성.
    assert_no_difference "RoleAssignment.count" do
      post role_assignments_path, params: { account_id: choi.id, role_key: "external_collaborator", scope_product_id: co0200.id }
    end
    assert_response :forbidden
  end

  # ── 4) grant 회수 즉시성: choi의 유일 grant 회수 → 라이브 세션의 다음 요청에서 빈 대시보드 fail-closed ──
  test "grant 회수 즉시성: choi 유일 grant(CO0200) 회수 → 재로그인 없이 다음 요청에서 빈 대시보드 fail-closed" do
    choi_acc = Account.find_by!(email: "choi@partner.example")
    co0200   = Product.find_by!(code: "CO0200")
    choi_sess  = open_session
    admin_sess = open_session
    sign_in(admin_sess, Account.find_by!(email: "song@cooa.dev")) # brand_admin → manage_members
    sign_in(choi_sess, choi_acc)

    # 초기: choi는 CO0200만 가시.
    choi_sess.get root_path
    choi_sess.assert_response :success
    assert_match "CO0200", choi_sess.response.body

    # 관리자가 choi의 유일 grant 회수(choi 라이브 세션은 유지).
    grant = choi_acc.role_assignments.find_by!(scope_product_id: co0200.id)
    assert_difference "RoleAssignment.count", -1 do
      admin_sess.delete role_assignment_path(grant)
    end
    admin_sess.assert_redirected_to members_path

    # choi의 다음 요청: 재로그인 없이 즉시 반영 — 여전히 인증되나 가시 제품 0(fail-closed·요청 간 stale 역할 없음).
    choi_sess.get root_path
    choi_sess.assert_response :success                  # grant 회수 ≠ 세션 폐기 → 인증 유지
    refute_match "CO0200", choi_sess.response.body      # 부여 제품 소멸
    refute_match "레티놀 3% 세럼", choi_sess.response.body # 타 제품도 전무 = fail-closed
    refute_match "시카 수딩 크림", choi_sess.response.body
  end
end
