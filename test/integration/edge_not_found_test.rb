require "test_helper"

# S6 404 스윕: 비존재 리소스가 전역 rescue 계층(E1)으로 우아하게 처리되는지 — html이면 한글 404 브랜드
# 페이지, 비-html(JSON/Turbo)이면 본문 없는 head 404. GET/POST/DELETE·bigint/uuid PK를 가로질러 확인
# (감사 인벤토리 ⑥ 비존재 id raw 404 미검증). setup=시드 + 김쿠아(owner) 로그인.
class EdgeNotFoundTest < ActionDispatch::IntegrationTest
  test "S6 GET /products/:id 비존재 → html 404 브랜드 페이지(한글 문구)" do
    get product_path(id: 999_999)
    assert_response :not_found
    assert_match "페이지를 찾을 수 없습니다", @response.body
  end

  test "S6 GET /versions/:id 비존재 → html 404 브랜드 페이지" do
    get component_version_path(id: 999_999)
    assert_response :not_found
    assert_match "페이지를 찾을 수 없습니다", @response.body
  end

  test "S6 POST /components/:id/versions 비존재 구성요소 → 404(find 실패 우아 처리)" do
    post component_component_versions_path(999_999) # find 실패가 version 빌드보다 먼저 → 404
    assert_response :not_found
  end

  test "S6 DELETE /role_assignments/:id 비존재 uuid → 404" do
    delete role_assignment_path(id: "00000000-0000-0000-0000-000000000000") # 정상 형식·미존재 → RecordNotFound
    assert_response :not_found
  end

  test "S6 비-html(JSON) 비존재 → head 404(본문 없음)" do
    get product_path(id: 999_999), as: :json
    assert_response :not_found
    assert_predicate @response.body.strip, :empty?, "JSON 소비자에 HTML 404 본문을 떠넘기지 않음"
  end
end
