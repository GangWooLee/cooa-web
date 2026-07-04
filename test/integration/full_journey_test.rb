require "test_helper"

# S3 전 체인 연속 통합: 조각 테스트(demo_flows·v15_edge·screens)로 흩어진 단계를 한 저니로 이어 붙여
# "업로드→피드백→미배정 리뷰요청→claim→피드백/해소→검토확인→새 버전(current 전환)→비교→신버전 피드백"의
# 상태·카운트 불변식을 연속 검증한다. 실 HTTP + 실 아트워크 업로드(box.jpg=image/jpeg, probe 무관)로 구동.
# 페르소나: kim(owner) 업로드/피드백 · park(contributor) 미배정 요청 · lee(approver+ra) claim/확인(SoD: park≠lee).
class FullJourneyTest < ActionDispatch::IntegrationTest
  # 매 호출마다 새 IO(요청당 1회 소비) — 두 번의 업로드에 각각 신선한 인스턴스 필요.
  def artwork_upload
    Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/box.jpg"), "image/jpeg")
  end

  test "S3 전 체인 저니: 업로드→어노테이션→미배정요청→claim→피드백/해소→confirm→새버전→비교→신버전 어노테이션" do
    kim  = Account.find_by!(email: "kim@cooa.dev")
    park = Account.find_by!(email: "park@cooa.dev")
    lee  = Account.find_by!(email: "lee@cooa.dev")
    product = Product.find_by!(code: "CO0001") # kim owner(tenant-wide) · park/lee tenant-wide 역할

    # 1) kim(owner): 새 구성요소 + 첫 버전(vN) 업로드 ────────────────────────
    assert_difference -> { product.components.count }, 1 do
      post product_components_path(product)
    end
    comp = product.components.order(:id).last
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "초안", artwork: artwork_upload } }
    end
    vN = comp.component_versions.order(:version_number).last
    assert vN.current?, "첫 업로드는 current"
    assert vN.artwork.attached?, "아트워크 첨부됨"

    # 2) kim: 어노테이션 생성(vN) + 첫 코멘트 ─────────────────────────────────
    assert_difference -> { vN.annotations.count }, 1 do
      post component_version_annotations_path(vN),
           params: { box_x: 10, box_y: 10, box_w: 8, box_h: 5, category: "디자인", body: "초기 피드백" }
    end
    ann = vN.annotations.order(:id).last
    assert_equal 1, ann.comments.count, "body가 있으면 첫 코멘트 생성"

    # 3) park로 전환 → 미배정 리뷰요청(vN) ────────────────────────────────────
    sign_in_as(park)
    assert_difference -> { ApprovalRequest.count }, 1 do
      post approval_requests_path, params: { component_version_id: vN.id } # 리뷰어 미지정
    end
    req = ApprovalRequest.find_by!(component_version_id: vN.id)
    assert_equal "pending", req.status
    assert_empty req.requested_reviewer_ids, "미배정 상태"

    # 4) lee로 전환 → claim(자기배정) ────────────────────────────────────────
    sign_in_as(lee)
    assert_difference -> { req.approval_request_reviewers.count }, 1 do
      post claim_approval_request_path(req)
    end
    assert_includes req.reload.requested_reviewer_ids, lee.user_id, "claim 후 lee가 지정 리뷰어"

    # 5) lee: 피드백 코멘트 추가 + 어노테이션 해소 ────────────────────────────
    assert_difference -> { ann.comments.count }, 1 do
      post annotation_comments_path(ann), params: { body: "확인했습니다 — 반영 필요" }
    end
    patch resolve_annotation_path(ann)
    assert ann.reload.resolved?, "해소 전이"

    # 6) lee: 검토 확인 → reviewed(SoD park≠lee, 콘텐츠 스냅샷 불변이라 stale 아님) ──
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status
    assert_equal 1, req.approval_steps.count

    # 7) kim으로 전환 → 새 버전(vN+1) 업로드 → current 전환 ───────────────────
    sign_in_as(kim)
    assert_difference -> { comp.component_versions.count }, 1 do
      post component_component_versions_path(comp),
           params: { component_version: { current: "1", change_reason: "피드백 반영", artwork: artwork_upload } }
    end
    v_next = comp.component_versions.order(:version_number).last
    assert_equal vN.version_number + 1, v_next.version_number, "버전 번호 +1"
    assert v_next.current?, "새 버전이 current"
    refute vN.reload.current?, "이전 버전 current 해제(단일성 불변식)"

    # 8) 비교 화면(구/신) 렌더 ────────────────────────────────────────────────
    get comparison_path(from_id: vN.id, to_id: v_next.id)
    assert_response :success

    # 9) 신버전에 어노테이션 ──────────────────────────────────────────────────
    assert_difference -> { v_next.annotations.count }, 1 do
      post component_version_annotations_path(v_next),
           params: { box_x: 5, box_y: 5, box_w: 4, box_h: 4, category: "기타", body: "신버전 확인" }
    end
  end

  test "S3 삭제된 구성요소로의 스테일 업로드 POST → 404 우아 처리(500 아님)" do
    product = Product.find_by!(code: "CO0001")
    post product_components_path(product)
    comp = product.components.order(:id).last
    delete component_path(comp) # 구성요소 삭제(버전·피드백 연쇄)

    # 스테일 폼: 방금 삭제된 구성요소로 새 버전 업로드 POST → Component.find 실패 → E1 전역 rescue 404.
    post component_component_versions_path(comp),
         params: { component_version: { current: "1", artwork: artwork_upload } }
    assert_response :not_found
  end
end
