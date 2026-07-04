require "test_helper"

# S7 빈 상태: (1) /brands/:id 해피패스 — 유일하게 미커버였던 라우트(dashboard#index 브랜드 스코프 별칭)가
# 정상 렌더되는지. (2) 제품 0 테넌트 대시보드 — 시드 후 전삭제(트랜잭션 내·롤백 안전)해도 대시보드가 빈
# 상태로 우아하게 렌더되는지(제품 행 전무·500 없음). setup=시드 + 김쿠아(owner) 로그인.
class EdgeEmptyStateTest < ActionDispatch::IntegrationTest
  test "S7 GET /brands/:id 해피패스 → 대시보드 렌더" do
    brand = Product.find_by!(name: "레티놀 3% 세럼") # 브랜드 루트(폴더)
    get brand_path(id: brand.id)
    assert_response :success
    assert_match "데이터 관리", @response.body, "브랜드 별칭 라우트도 대시보드(index)를 렌더"
  end

  test "S7 제품 0 대시보드 → 빈 상태 우아 렌더(제품 행 전무)" do
    Product.destroy_all # dependent: :destroy 연쇄 · 트랜잭션 내라 롤백 안전 · scope grant는 FK cascade 정리
    assert_equal 0, Product.count

    get root_path
    assert_response :success
    assert_match "데이터 관리", @response.body, "제품 0이어도 대시보드 셸은 렌더"
    refute_match "레티놀 3% 세럼", @response.body, "제품 행이 하나도 없어야 함"
  end
end
