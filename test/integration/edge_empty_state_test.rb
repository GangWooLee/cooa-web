require "test_helper"

# S7 빈 상태: (1) /brands/:id 해피패스 — 유일하게 미커버였던 라우트(dashboard#index 브랜드 스코프 별칭)가
# 정상 렌더되는지. (2) 제품 0 테넌트 대시보드 — 시드 후 전삭제(트랜잭션 내·롤백 안전)해도 대시보드가 빈
# 상태로 우아하게 렌더되는지(제품 행 전무·500 없음). setup=시드 + 김쿠아(owner) 로그인.
class EdgeEmptyStateTest < ActionDispatch::IntegrationTest
  test "S7 GET /brands/:id 해피패스 → 작업실 페이지 렌더(서브트리 스코프)" do
    brand = Product.find_by!(name: "레티놀 3% 세럼") # 작업실 루트(폴더)
    get workspace_path(id: brand.workspace_id)
    assert_response :success
    # D2: 작업실 페이지 헤더 타이틀 = 작업실명(구 하드코드 "데이터 관리" 대체). 타이틀 태그도 작업실명이라
    # "데이터 관리"(홈 타이틀·헤더)는 작업실 문맥 어디에도 없어야.
    assert_match "레티놀 3% 세럼", @response.body, "작업실 페이지 헤더/타이틀 = 작업실명"
    refute_match "데이터 관리", @response.body, "작업실 문맥엔 '데이터 관리' 부재(D2 타이틀 통합)"
    assert_match "멤버 초대·관리", @response.body, "작업실 헤더 멤버 관리 어포던스(구 '작업실' 배지 대체)"
    # 메인 트리(테이블)는 그 브랜드 서브트리만 — 사이드바 전체 트리(모든 브랜드)와 구분해 테이블 행으로 단언.
    table_ids = css_select("table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
    assert_includes table_ids, brand.id.to_s, "그 브랜드 루트는 메인 트리에 렌더"
    vitc_id = Product.find_by!(name: "비타민C 브라이트닝 앰플").id.to_s
    assert_not_includes table_ids, vitc_id, "타 브랜드 루트는 메인 트리(서브트리) 밖 — 부재"
  end

  test "S7 제품·작업실 0 대시보드 → 빈 상태 우아 렌더" do
    # D3: 작업실이 first-class라 제품만 지우면 빈 작업실이 카드로 남는다. 완전 빈 테넌트는 제품→작업실 순으로
    # 비운다(products.workspace_id RESTRICT라 제품 먼저). 둘 다 트랜잭션 내라 롤백 안전(scope grant는 FK cascade).
    Product.destroy_all
    Workspace.destroy_all
    assert_equal 0, Product.count
    assert_equal 0, Workspace.count

    get root_path
    assert_response :success
    assert_match "작업실", @response.body, "완전 빈 테넌트여도 대시보드 셸은 렌더"
    assert_match "아직 작업실이 없습니다", @response.body, "빈 상태 안내 노출"
    refute_match "레티놀 3% 세럼", @response.body, "삭제된 작업실/제품명은 어디에도 없어야"
  end
end
