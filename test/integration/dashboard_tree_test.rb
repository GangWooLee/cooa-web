require "test_helper"

# H2 게이트: tenant-wide(kim) 대시보드는 멀티레벨·멀티루트 전 트리를 렌더해도 N+1이 없어야 한다.
# 시드 트리: 레티놀 세럼(루트·폴더) → 미국(폴더) → [30ml CO0000, 50ml CO0000L] · 일본 CO0001(리프);
#            비타민C(루트·폴더) → 중국 CO0100; 시카(루트·폴더) → 미국 CO0200. (폴더깊이 2 + 멀티루트)
#
# ── load-bearing RED 실증(2026-07-04) ──
# Product.tree_preorder + load_dashboard_rows를 구버전(association .children 재귀 walk + visible_roots 전달)으로
# 되돌리고 이 테스트를 돌리면 Prosopite가 raise한다(실측):
#   Prosopite::NPlusOneQueriesError: N+1 queries detected
#     SELECT "products".* WHERE "products"."parent_id" = ?        (레벨 2+ children 재쿼리 — 6회)
#     SELECT "product_members".* WHERE "product_members"."product_id" = ?  (하위 리프 담당자 — 5회)
#     SELECT "components".* WHERE "components"."product_id" = ?    (하위 리프 구성요소 — 5회)
#   call stack: app/models/product.rb:tree_preorder · app/views/dashboard/_row.html.erb
# 원인: 구현이 roots만 1레벨 프리로드해 하위 노드(n.children 경유 query-2 인스턴스)는 children·담당자·구성요소가
# 프리로드되지 않아 노드마다 재쿼리. 현 구현(flat 1회 로드 + parent_id 그룹핑 + parent 타깃 in-memory 배선)으로
# 원복하면 GREEN. 스코프 계정(choi·얕은 트리) 경로는 scoped_access_test가 별도 게이트(구현엔 잠복 미검출이던 축).
class DashboardTreeTest < ActionDispatch::IntegrationTest
  test "tenant-wide 대시보드(멀티레벨·멀티루트 전 트리) 렌더는 N+1을 내지 않음" do
    sign_in_as(Account.find_by!(email: "kim@cooa.dev")) # 전 제품 가시 → 재루팅 없이 실제 3레벨 트리를 walk
    assert_no_n_plus_one { get root_path }
    assert_response :success

    # 게이트가 얕은 트리로 위장되지 않도록 멀티레벨·멀티루트가 실제 렌더됐음을 확인(load-bearing).
    body = response.body
    assert_match "레티놀 3% 세럼", body        # 루트1(폴더)
    assert_match "비타민C 브라이트닝 앰플", body # 루트2(폴더)
    assert_match "시카 수딩 크림", body         # 루트3(폴더)
    assert_match "CO0000", body                 # 레티놀 › 미국(폴더) › 30ml — 폴더깊이 2 하위 리프
  end
end
