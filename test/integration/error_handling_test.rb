require "test_helper"

# E-트랙 에러 핸들링 구조화(docs/error-handling.md) — 신규 동작 회귀 게이트:
#  E1 전역 rescue 계층(RecordNotFound → 404: html=브랜드 페이지 / 비html=head)
#  E4 도메인 액터 가드 통일(미브리지 계정의 감사 도메인 쓰기 = fail-closed 403·미기록)
#  E3 폼 실패 = flash alert + non-bang(피드백 생성/해소 리팩터 회귀 잠금)
class ErrorHandlingTest < ActionDispatch::IntegrationTest
  # ── E1 전역 rescue 계층 ──
  test "E1 존재하지 않는 리소스(html) → 404 브랜드 페이지 렌더" do
    get product_path(id: 999_999_999)
    assert_response :not_found
    assert_match "페이지를 찾을 수 없습니다", @response.body, "한글 브랜드 404 파일이 렌더되어야 함"
    assert_match "COOA", @response.body
  end

  test "E1 존재하지 않는 리소스(비html/JSON) → head 404(본문 없음)" do
    patch move_product_path(id: 999_999_999), as: :json, params: { parent_id: "" }
    assert_response :not_found
    assert_predicate @response.body.strip, :empty?, "fetch/JSON 소비자에 HTML 404 본문을 떠넘기지 않음"
  end

  # ── E4 도메인 액터 가드 통일(require_domain_actor) ──
  # 감사(allow) 도메인 쓰기 경로는 연결 User가 있는 계정만 수행. 미브리지 owner(권한은 있으나 도메인
  # 액터 없음)가 AuditLog.record!의 fail-closed raise(500)에 닿기 전, before_action이 403으로 막는다.
  test "E4 미브리지 계정의 초대 생성 = 403·감사/초대 미기록(fail-closed)" do
    kim = Account.find_by!(email: "kim@cooa.dev")     # owner(manage_members 보유)
    kim.update_columns(user_id: nil)                  # 도메인 액터만 제거(role_assignment=계정 기반이라 owner 유지)
    assert_no_difference [ "AuditLog.count", "Invitation.count" ] do
      post invitations_path, params: { email: "new@x.dev", role_key: "member" }
    end
    assert_response :forbidden
  end

  test "E4 미브리지 계정의 리뷰 요청 = 403(감사 도메인 쓰기 차단)" do
    v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
               .component_versions.find_by!(version_number: 5)
    kim = Account.find_by!(email: "kim@cooa.dev")
    kim.update_columns(user_id: nil)
    assert_no_difference [ "ApprovalRequest.count", "AuditLog.count" ] do
      post approval_requests_path, params: { component_version_id: v.id }
    end
    assert_response :forbidden
  end

  # ── E3 피드백 생성/해소 non-bang 리팩터: 정상 경로 회귀 잠금 ──
  test "E3 피드백 생성(정상) — 어노테이션+첫 코멘트 생성 후 되돌림" do
    v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
               .component_versions.find_by!(version_number: 5)
    assert_difference -> { v.annotations.count }, 1 do
      post component_version_annotations_path(v),
           params: { box_x: 10, box_y: 12, box_w: 8, box_h: 5, category: "디자인", body: "첫 피드백" }
    end
    ann = v.annotations.order(:id).last
    assert_equal 1, ann.comments.count, "body가 있으면 첫 코멘트도 생성"
    assert_equal "첫 피드백", ann.comments.first.body
    assert_response :redirect
  end

  test "E3 피드백 해소(정상) — resolved 전이" do
    v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
               .component_versions.find_by!(version_number: 5)
    ann = v.annotations.create!(box_x: 1, box_y: 1, box_w: 1, box_h: 1, category: "기타",
                                created_by: User.find_by!(email: "kim@cooa.dev"), seq: 1)
    patch resolve_annotation_path(ann)
    assert ann.reload.resolved?, "해소 전이"
    assert_response :redirect
  end
end
