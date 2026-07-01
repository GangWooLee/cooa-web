require "test_helper"

# "내게 요청된 리뷰" 수신함: 내가 지정 리뷰어인 pending 요청만 보임(+ 부정 쌍둥이). setup=kim 로그인.
class ReviewsInboxTest < ActionDispatch::IntegrationTest
  setup do
    @v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                .component_versions.find_by!(version_number: 5)
    lee = User.find_by!(email: "lee@cooa.dev")
    post approval_requests_path, params: { component_version_id: @v.id, reviewer_ids: [lee.id] } # kim → lee 요청(버전 앵커)
  end

  test "지정된 리뷰어(lee)의 수신함에 요청이 보임" do
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    get reviews_path
    assert_response :success
    assert_match "내게 요청된 리뷰", response.body
    assert_match "CO0001", response.body # 방금 요청한 버전
  end

  test "요청받지 않은 사용자(park)의 수신함은 비어있음" do
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    get reviews_path
    assert_response :success
    assert_match "요청된 리뷰가 없습니다", response.body
  end
end
