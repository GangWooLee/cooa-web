require "test_helper"

# 버전 리뷰 워크플로(버전 앵커): 리뷰는 버전에 붙는다 — 디자이너는 스크리닝 없이 요청(RA가 검토 중 스크리닝).
# 콘텐츠 스냅샷, 신원 SoD, stale 경량 가드, 감사, 요청받음=검토권한(소프트). setup=시드 + 김쿠아(owner) 로그인.
class ApprovalWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    @v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                .component_versions.find_by!(version_number: 5)
  end

  # 스크리닝 없이 버전에 직접 리뷰 요청(재앵커 핵심).
  def submit! = post approval_requests_path, params: { component_version_id: @v.id }
  def request_for = ApprovalRequest.find_by!(component_version_id: @v.id)

  test "스크리닝 없이 리뷰 요청 → pending (+ 콘텐츠 스냅샷 캡처)" do
    submit!
    req = request_for
    assert_equal "pending", req.status
    assert req.reviewed_content_snapshot_hash.present?
    assert req.reviewed_artifact_digest.present?
  end

  test "리뷰어 지정 → requested_reviewer로 저장" do
    lee = User.find_by!(email: "lee@cooa.dev")
    post approval_requests_path, params: { component_version_id: @v.id, reviewer_ids: [ lee.id ] }
    assert_includes request_for.requested_reviewer_ids, lee.id
  end

  # 권한 시프트의 핵심: 요청받은 제품 담당자는 approve verb가 없어도(park=contributor) 확인 가능.
  test "요청받은 담당자(contributor)가 검토 확인 가능" do
    park = User.find_by!(name: "박쿠아")
    post approval_requests_path, params: { component_version_id: @v.id, reviewer_ids: [ park.id ] }
    req = request_for
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status
    assert_equal park.id, req.approval_steps.first.approver_id
  end

  # SoD: 요청자 자신을 리뷰어로 지정해도 strip + 본인 확인 불가.
  test "자기 자신 리뷰어 지정은 strip되고 SoD로 확인 불가" do
    kim = User.find_by!(name: "김쿠아")
    post approval_requests_path, params: { component_version_id: @v.id, reviewer_ids: [ kim.id ] }
    req = request_for
    refute_includes req.requested_reviewer_ids, kim.id
    post confirm_approval_request_path(req) # 여전히 kim(요청자)
    assert_response :forbidden
  end

  # 비요청·비approver(song=brand_admin, approve 없음)는 확인 불가.
  test "요청받지 않은 비approver는 확인 불가" do
    lee = User.find_by!(email: "lee@cooa.dev")
    post approval_requests_path, params: { component_version_id: @v.id, reviewer_ids: [ lee.id ] }
    req = request_for
    sign_in_as(Account.find_by!(email: "song@cooa.dev"))
    post confirm_approval_request_path(req)
    assert_response :forbidden
    assert_equal "pending", req.reload.status
  end

  test "M2 SoD: 요청자(김쿠아 owner)는 본인 확인 불가; 이쿠아(리뷰어)는 가능" do
    submit!
    req = request_for
    post confirm_approval_request_path(req) # still 김쿠아
    assert_response :forbidden
    assert_equal "pending", req.reload.status

    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status
    assert_equal 1, req.approval_steps.count
    assert_equal User.find_by!(name: "이쿠아").id, req.approval_steps.first.approver_id
    assert_equal "confirmed", req.approval_steps.first.decision
  end

  test "stale: 리뷰 요청 후 콘텐츠 변경 시 확인 차단(pending 유지 + deny 감사)" do
    submit!
    req = request_for
    @v.label_texts.first.update!(content: "CHANGED AFTER REQUEST")
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post confirm_approval_request_path(req)
    assert_equal "pending", req.reload.status, "stale면 확인되면 안 됨"
    assert AuditLog.where(outcome: "deny", denial_reason: "stale_reviewed_tuple").exists?
  end

  test "전이는 감사 로그에 기록(allow)" do
    assert_difference -> { AuditLog.where(action: "submit_for_approval", outcome: "allow").count }, 1 do
      submit!
    end
    req = request_for
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    assert_difference -> { AuditLog.where(action: "confirm_review", outcome: "allow", resource_type: "ApprovalRequest").count }, 1 do
      post confirm_approval_request_path(req)
    end
  end

  # N+1 게이트(R5 · docs/dev-discipline.md): 버전 리뷰 패널 렌더가 연관(담당자·피드백·리뷰어)을
  # 프리로드하는지 강제. 컨트롤러 includes가 빠지면 prosopite가 raise → 실패. pending 상태로 요청해
  # 리뷰어/담당자 루프가 실제로 돌게 한다.
  test "버전 리뷰 패널 렌더는 N+1 없음 (critical path 게이트)" do
    submit!
    assert_no_n_plus_one { get component_version_path(@v) }
    assert_response :success
  end

  # 버전 뷰가 리뷰 패널을 상태별로 렌더(ERB/정책/아바타 오류 포착) — 스크리닝 없이도 요청 버튼 노출.
  test "버전 뷰가 리뷰 패널을 상태별로 렌더" do
    get component_version_path(@v)
    assert_response :success
    assert_match "리뷰 요청", response.body # 스크리닝 없이도 요청 버튼(김쿠아 owner)
    submit!
    get component_version_path(@v)
    assert_response :success
    assert_match "리뷰 대기", response.body # pending; 김쿠아=요청자 → SoD note
    assert_match "SoD", response.body
  end
end
