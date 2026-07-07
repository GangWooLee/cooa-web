require "test_helper"

# W2 페르소나 저니 — 라이프사이클 체인(상태가 이어지는 저니, 단발 인가 재검증 아님).
#   J1 owner 제네시스: 작업실→루트폴더→리프제품(JP)→속성→구성요소→버전(box.jpg)→run_screening(JP)→피드백→
#      리뷰요청(lee 지정)→lee 검토확인 을 한 체인으로. (full_journey는 기존 제품서 claim 경로 — 여기는 제로부터
#      생성 + 스크리닝을 체인에 엮음: 겹치지 않는 축.)
#   J8 설정 멀티세션: 프로필 편집 관통 → sign_out_all(token_version bump) → 다른 기기 세션 즉시 폐기 → 재로그인
#      복구. (edge_session은 token_version을 직접 bump — 여기는 실제 sign_out_all 엔드포인트 + 두 번째 세션.)
class JourneysLifecycleTest < ActionDispatch::IntegrationTest
  def fresh_artwork = fixture_file_upload("box.jpg", "image/jpeg")

  # ── J1: owner(kim) 제네시스 풀 체인 ─────────────────────────────────────────
  test "J1 owner 제네시스: 작업실→폴더→리프→구성요소→버전업로드→JP스크리닝→피드백→리뷰요청→lee 확인" do
    lee_acc  = Account.find_by!(email: "lee@cooa.dev")   # ra_reviewer+approver(tenant-wide) = 리뷰어 후보
    lee_user = lee_acc.user

    # 1) 새 작업실 생성(kim=owner, 부모 setup 로그인) → 그 작업실로 진입.
    assert_difference "Workspace.count", 1 do
      post workspaces_path, params: { name: "제네시스 라인" }
    end
    ws = Workspace.find_by!(name: "제네시스 라인")
    assert_redirected_to workspace_path(ws)

    # 2) 이 작업실에 루트 폴더 생성(workspace_id 스레딩 = 툴바 경로).
    assert_difference "Product.count", 1 do
      post products_path, params: { product: { kind: "folder", name: "레티놀 신규" }, workspace_id: ws.id }
    end
    folder = Product.order(:id).last
    assert_equal ws.id, folder.workspace_id, "루트 폴더는 이 작업실 귀속"

    # 3) 폴더 아래 리프 제품(코드·JP) 생성 — JP라야 run_screening이 국가 fact를 돈다.
    assert_difference "Product.count", 1 do
      post products_path, params: { product: { kind: "item", parent_id: folder.id, name: "일본 SKU",
                                               code: "CO9001", country: "JP", channel: "QTEN" } }
    end
    leaf = Product.find_by!(code: "CO9001")
    assert_equal folder.id, leaf.parent_id
    assert_equal folder.id, leaf.brand_root.id, "리프의 브랜드 루트 = 생성한 폴더"

    # 4) 커스텀 속성(Notion식) 즉시 추가.
    assert_difference "ProductProperty.count", 1 do
      post product_product_properties_path(leaf)
    end

    # 5) 구성요소 + 첫 버전(실 아트워크 box.jpg) 업로드 → current.
    assert_difference -> { leaf.components.count }, 1 do
      post product_components_path(leaf)
    end
    comp = leaf.components.order(:id).last
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "초안", artwork: fresh_artwork } }
    end
    v = comp.component_versions.order(:version_number).last
    assert v.current?, "첫 업로드는 current"
    assert v.artwork.attached?, "아트워크 첨부됨"

    # 6) JP 스크리닝 실행(룰엔진) — ScreeningRun 1건 생성.
    assert_difference -> { v.screening_runs.count }, 1 do
      post run_screening_component_version_path(v)
    end

    # 7) 아트워크 위 바운딩박스 피드백 생성(+첫 코멘트).
    assert_difference -> { v.annotations.count }, 1 do
      post component_version_annotations_path(v),
           params: { box_x: 12, box_y: 20, box_w: 8, box_h: 4, category: "인허가", body: "DMAH 명칭 확인 필요" }
    end

    # 8) 리뷰 요청(lee 지정) → pending, lee가 지정 리뷰어. (SoD: kim=요청자 → 본인 확인 불가.)
    assert_difference "ApprovalRequest.count", 1 do
      post approval_requests_path, params: { component_version_id: v.id, reviewer_ids: [ lee_user.id ] }
    end
    req = ApprovalRequest.find_by!(component_version_id: v.id)
    assert_equal "pending", req.status
    assert_includes req.requested_reviewer_ids, lee_user.id

    # 9) lee(리뷰어)로 전환 → 검토 확인 → reviewed(승인 단계 1건, approver=lee).
    sign_in_as(lee_acc)
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status
    assert_equal 1, req.approval_steps.count
    assert_equal lee_user.id, req.approval_steps.first.approver_id
  end

  # ── J8: 계정 설정 저니 + 전체 로그아웃 revocation ───────────────────────────
  test "J8 설정: 프로필 편집 관통 → sign_out_all이 다른 기기 세션을 즉시 폐기 → 재로그인 복구" do
    kim = Account.find_by!(email: "kim@cooa.dev")

    # 두 번째 기기 세션(같은 kim) — 편집·로그아웃은 세션 A(기본), 폐기 검증은 세션 B.
    device_b = open_session
    device_b.post session_path, params: { account_id: kim.id }
    device_b.get root_path
    device_b.assert_response :success, "B 기기: 로그인 성립"

    # A: 프로필 이름 편집 → 관통 저장 + 설정 화면 반영.
    patch settings_path, params: { account: { display_name: "쿠아 김편집" } }
    assert_redirected_to settings_path
    assert_equal "쿠아 김편집", kim.reload.display_name, "표시 이름이 accounts 컬럼에 관통 저장"
    get settings_path
    assert_response :success
    assert_select "input[name=?][value=?]", "account[display_name]", "쿠아 김편집"

    # A: 모든 기기에서 로그아웃 → token_version bump + 현재 세션 리셋 → 로그인 요구.
    old_tv = kim.reload.token_version
    post sign_out_all_path
    assert_response :see_other
    assert_redirected_to new_session_path
    assert_operator kim.reload.token_version, :>, old_tv, "logout-everywhere는 token_version을 올린다"

    # B: 다음 요청에서 스냅샷 token_version 불일치 → 재로그인 없이 즉시 폐기(매요청 revocation 검사).
    device_b.get root_path
    device_b.assert_response :see_other
    device_b.assert_redirected_to new_session_path, "B 기기 세션은 다음 요청에서 폐기(logout-everywhere)"

    # B: 재로그인 → 새 token_version 스냅샷 → 정상 복구.
    device_b.post session_path, params: { account_id: kim.id }
    device_b.get root_path
    device_b.assert_response :success, "재로그인 후 복구"
  end
end
