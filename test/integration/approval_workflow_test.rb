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

  # Stage 4 T2 화이트리스트: 후보 풀(권한 평면) 밖의 id는 서버측에서 strip. choi는 CO0200 스코프라
  # CO0001(레티놀 브랜드) 버전의 후보가 아니다 → 리뷰어 지정 시도해도 걸러진다(임의 id 방어).
  test "비후보(타 브랜드 스코프) id는 화이트리스트에서 strip" do
    choi = User.find_by!(email: "choi@partner.example") # external_collaborator @ CO0200 — 레티놀 후보 아님
    lee  = User.find_by!(email: "lee@cooa.dev")           # tenant-wide — 후보
    post approval_requests_path, params: { component_version_id: @v.id, reviewer_ids: [ choi.id, lee.id ] }
    ids = request_for.requested_reviewer_ids
    refute_includes ids, choi.id, "후보 풀 밖 id는 지정될 수 없어야 함"
    assert_includes ids, lee.id
  end

  # external_collaborator 제외(REF 시나리오 ③): choi는 external뿐이라 자기 스코프 체인(CO0200)에서도 후보가
  # 아니다 → 그 체인 버전의 리뷰어 지정에서도 strip(external 지정=소프트그랜트 우회 차단). tenant-wide lee는 남음.
  test "external(choi)은 자기 스코프 체인(CO0200) 버전에서도 화이트리스트에서 strip" do
    v200 = Product.find_by!(code: "CO0200").components.find_by!(component_type: "outer_box")
                  .component_versions.find_by!(current: true)
    choi = User.find_by!(email: "choi@partner.example")
    lee  = User.find_by!(email: "lee@cooa.dev") # tenant-wide → CO0200 체인 후보
    post approval_requests_path, params: { component_version_id: v200.id, reviewer_ids: [ choi.id, lee.id ] }
    ids = ApprovalRequest.find_by!(component_version_id: v200.id).requested_reviewer_ids
    refute_includes ids, choi.id, "external_collaborator는 자기 스코프 체인에서도 지정 불가"
    assert_includes ids, lee.id
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

  # D2-A(리뷰 F4): 개명(Account display_name)이 저작권 뷰까지 일관 반영되는지 — hero v5는 kim이 created_by이고
  # a3 댓글 author이며 리뷰 요청 시 submitter라, 세 저작권 채널이 모두 kim으로 겹친다(개명=한 번에 검증).
  test "D2 개명 일관: kim 개명 후 버전 created_by·댓글 author·리뷰 요청자 표기가 새 이름" do
    kim_acct = Account.find_by!(email: "kim@cooa.dev")
    kim_user = kim_acct.user
    old_name = kim_user[:name] # 도메인 원값(김쿠아)

    patch settings_path, params: { account: { display_name: "쿠아 김대표" } } # accounts 컬럼 저장
    submit! # 리뷰 요청(요청자=kim)

    get component_version_path(@v)
    assert_response :success
    # created_by(kim)·댓글 author(kim, a3 두 번째 코멘트)·리뷰 요청자(kim) 모두 새 이름으로.
    assert_includes response.body, "쿠아 김대표"
    # 옛 이름(김쿠아)은 kim 저작권 표기에서 잔존하지 않는다(다른 인물 song/lee/park은 원 이름 유지 — "쿠아" 접미 공유하나
    # "김쿠아"는 kim 전용). 개명 리졸버가 저작권 뷰까지 관통했다는 음성 증거.
    refute_includes response.body, old_name

    # 리졸버는 읽기 전용 — users 컬럼(도메인 원값)은 불변.
    assert_equal old_name, kim_user.reload[:name]
  end

  # D2-A(R5): 비교 화면은 from 버전 어노테이션의 author를 다수 렌더(hero v5=5건, author song/lee/kim/park).
  # 표시 리졸버가 account-우선이 되며 author→account 프리로드가 없으면 N+1 → prosopite raise. 게이트로 고정.
  test "D2 비교 화면 렌더는 N+1 없음 (author→account 프리로드 게이트)" do
    v6 = @v.component.component_versions.find_by!(version_number: 6)
    assert_no_n_plus_one { get comparison_path(from_id: @v.id, to_id: v6.id) }
    assert_response :success
  end

  # 반영 어노테이션 버전 프리로드 게이트(perf 발견 7): 버전 상세는 반영완료(resolved) 어노테이션마다
  # resolved_in_version.vlabel을 렌더한다 — 컨트롤러 includes에서 :resolved_in_version이 빠지면 반영건마다
  # `component_versions WHERE id=N` 단건 재쿼리 → Prosopite raise. 시드는 반영 4건이 전부 v6 귀속이라
  # 재쿼리가 쿼리캐시로 1회만 실발화해 미검출 — 한 건을 v4로 재귀속해 서로 다른 두 버전이 게이트를
  # 실제로 물게 한다(load-bearing).
  test "버전 상세의 반영완료 어노테이션 렌더는 component_versions 단건 반복이 없음" do
    v4 = @v.component.component_versions.find_by!(version_number: 4)
    @v.annotations.where(status: "resolved").order(:seq).first.update!(resolved_in_version: v4)

    assert_no_n_plus_one { get component_version_path(@v) }
    assert_response :success
    assert_match "에서 반영 확인", response.body # resolved 표기가 실제 렌더됨(게이트 load-bearing)
  end
end
