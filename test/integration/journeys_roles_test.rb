require "test_helper"

# W2 페르소나 저니 — 순수-단일역할 신원의 능력 체인(han/yu/choi). 단발 allow/deny 전수는 authorization_matrix
# 소관이라, 여기선 "생성물이 다음 스텝 입력"인 체인·기존 저니가 안 다룬 축만 잡는다.
#   J3 external(choi): 자기 스코프 제품(CO0200)에 열람·업로드·피드백 O · 조상/타제품 비가시 · run_screening deny · 리뷰요청 O
#      (run_screening=external 상한 밖 → deny · 리뷰요청 route_for_review=상한 안 → 요청 생성, SoD로 본인 확인은 deny). (scoped_access는 choi 읽기 + 타제품 쓰기-deny만 — 여기는 choi의 자기제품 쓰기 능력.)
#   J4 viewer(yu): 대시보드→작업실→제품→버전→스크리닝→비교 읽기 순회 전부 200 · 대표 쓰기 2건 deny.
#   J5 assignee(han): 트리 편집(manage_product/upload_version) O · 멤버 관리 deny · 리뷰 라운드트립 참여(요청받음=확인).
class JourneysRolesTest < ActionDispatch::IntegrationTest
  # ── J3: external_collaborator(choi @ CO0200) ────────────────────────────────
  test "J3 external(choi): CO0200 열람·업로드·피드백 O · 조상/타제품 비가시 · 스크리닝 deny · 리뷰요청 O(route_for_review)" do
    choi   = Account.find_by!(email: "choi@partner.example")
    co0200 = Product.find_by!(code: "CO0200")
    cica   = Product.find_by!(name: "시카 수딩 크림") # CO0200의 (비가시) 조상 브랜드 루트
    co0001 = Product.find_by!(code: "CO0001")           # 타 제품
    comp   = co0200.components.find_by!(component_type: "outer_box")
    v      = comp.component_versions.find_by!(current: true)
    sign_in_as(choi)

    # 열람(view_product / view_component_version)
    get product_path(co0200)
    assert_response :success
    get component_version_path(v)
    assert_response :success

    # 업로드(external upload_version) — 새 버전 저장
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "외부 시안", artwork: fresh_artwork } }
    end

    # 피드백(external leave_feedback)
    assert_difference -> { v.annotations.count }, 1 do
      post component_version_annotations_path(v),
           params: { box_x: 10, box_y: 10, box_w: 5, box_h: 5, category: "디자인", body: "외부 협력 피드백" }
    end

    # 조상(시카 루트)·타 제품(CO0001) 비가시 → GET html deny는 root 리다이렉트
    get product_path(cica)
    assert_redirected_to root_path
    get product_path(co0001)
    assert_redirected_to root_path

    # run_screening은 external 상한(matrix) 밖 → 비-GET deny=403, 부작용 없음
    post run_screening_component_version_path(v)
    assert_response :forbidden

    # 리뷰 요청(route_for_review)은 external 상한 안 — "다 올렸으니 검토해 주세요" 루프를 제품 안으로
    # (ComponentVersionPolicy#submit_for_approval? = submit_for_approval ∨ route_for_review). ApprovalRequest 생성.
    assert_difference "ApprovalRequest.count", 1 do
      post approval_requests_path, params: { component_version_id: v.id }
    end
    assert_response :see_other # redirect_back → 303(see_other)
    req = ApprovalRequest.find_by!(component_version_id: v.id)
    assert_equal "pending", req.status

    # SoD 불변: choi는 approve verb 없고 본인이 요청자(submitter)라 본인 요청을 확인할 수 없다(confirm_review? deny).
    post confirm_approval_request_path(req)
    assert_response :forbidden
    assert_equal "pending", req.reload.status, "SoD: 요청자 본인 확인 불가 — 여전히 pending"
  end

  # ── J4: viewer(yu, tenant-wide) 읽기 순회 ───────────────────────────────────
  test "J4 viewer(yu): 대시보드→작업실→제품→버전→스크리닝→비교 전부 200 · 대표 쓰기 2건 deny" do
    yu      = Account.find_by!(email: "yu@cooa.dev")
    retinol = Product.find_by!(name: "레티놀 3% 세럼")
    co0001  = Product.find_by!(code: "CO0001")
    hero    = co0001.components.find_by!(component_type: "outer_box")
    v5      = hero.component_versions.find_by!(version_number: 5)
    v6      = hero.component_versions.find_by!(version_number: 6)
    sign_in_as(yu)

    # 읽기 순회 — 전부 200(viewer는 view_* 4종 보유)
    get root_path
    assert_response :success
    get workspace_path(retinol.workspace_id)
    assert_response :success
    get product_path(co0001)
    assert_response :success
    get component_version_path(v5)
    assert_response :success
    get screening_component_version_path(v5)
    assert_response :success
    get comparison_path(from_id: v5.id, to_id: v6.id) # 비교는 양 버전 view_component_version 인가
    assert_response :success

    # 대표 쓰기 2건 deny(전수는 authorization_matrix) — run_screening·products#create
    post run_screening_component_version_path(v5)
    assert_response :forbidden
    assert_no_difference "Product.count" do
      post products_path, params: { product: { kind: "item", name: "뷰어 시도" } }
    end
    assert_response :forbidden
  end

  # ── J5: assignee(han, tenant-wide) 트리 편집 + 리뷰 라운드트립 ───────────────
  test "J5 assignee(han): 트리 편집 O · 멤버 관리 deny · 리뷰 라운드트립(요청받음=검토 확인)" do
    han      = Account.find_by!(email: "han@cooa.dev")
    kim      = Account.find_by!(email: "kim@cooa.dev")
    retinol  = Product.find_by!(name: "레티놀 3% 세럼")
    co0001   = Product.find_by!(code: "CO0001")
    v5       = co0001.components.find_by!(component_type: "outer_box").component_versions.find_by!(version_number: 5)
    han_user = han.user

    # (1) 트리 편집 — 폴더 자식 생성(manage_product) · 구성요소 추가·버전 업로드(upload_version)
    sign_in_as(han)
    assert_difference "Product.count", 1 do
      post products_path, params: { product: { kind: "folder", parent_id: retinol.id, name: "한 담당 폴더" } }
    end
    assert_difference -> { co0001.components.count }, 1 do
      post product_components_path(co0001)
    end
    comp = co0001.components.order(:id).last
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "담당 편집", artwork: fresh_artwork } }
    end

    # (2) 멤버 관리 deny(assignee는 manage_members 없음)
    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "x@han.dev", role_key: "contributor" }
    end
    assert_response :forbidden

    # (3) 리뷰 라운드트립: kim이 han 지정 요청 → han 검토 확인(요청받음=소프트 그랜트, approve verb 없어도)
    sign_in_as(kim)
    post approval_requests_path, params: { component_version_id: v5.id, reviewer_ids: [ han_user.id ] }
    req = ApprovalRequest.find_by!(component_version_id: v5.id)
    assert_includes req.requested_reviewer_ids, han_user.id, "assignee도 리뷰어 후보(external·viewer-only 계정만 제외)"

    sign_in_as(han)
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status, "요청받은 담당 편집자는 검토 확인 가능"
    assert_equal han_user.id, req.approval_steps.first.approver_id
  end
end
