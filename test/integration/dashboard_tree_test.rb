require "test_helper"

# 컨텍스트-본문 정합 + N+1 게이트: tenant-wide(kim) 셸의 트리 본문은 두 축 모두에서 N+1 없이 렌더돼야 하고,
# 동시에 **진입한 작업실로만** 스코프돼야 한다(F1 회귀 방지 — 리프 상세 풀요청이 전 작업실을 쏟아내던 결함).
# 시드 트리: 레티놀 3% 세럼(루트·폴더) → 미국(폴더) → [30ml CO0000, 50ml CO0000L] · 일본 CO0001(리프);
#            비타민C(루트·폴더) → 중국 CO0100; 시카(루트·폴더) → 미국 CO0200. (시드 작업실은 전부 1루트)
#
# ── load-bearing RED 실증(2026-07-05 재구도) ──
# F1 픽스로 두 N+1 축의 게이트 위치가 서로 다른 진입점으로 갈렸다. 이 파일은 각 축을 그 진입점에 고정한다:
#   · 멀티레벨 축 = 제품 상세 풀요청(product_path 리프). load_dashboard_rows가 그 리프의 작업실로 스코프하되
#     폴더깊이 2 서브트리(레티놀 › 미국 › 30ml)를 flat 1회 로드 + parent_id 그룹핑으로 walk → 하위 레벨의
#     children/담당자/구성요소 재쿼리 0건. tree_preorder를 구버전(association .children 재귀 walk)으로
#     되돌리면 Prosopite가 raise(레벨 2+ children·product_members·components 각 재쿼리).
#   · 멀티루트 축 = 작업실 페이지(/workspaces/:id). 한 작업실이 복수 루트를 담을 때 그 전 루트 서브트리를
#     N+1 없이 렌더. 시드 작업실은 전부 1루트뿐이라 2루트 작업실을 테스트 내 생성(multi_root_workspace_test
#     픽스처 패턴 재사용).
# 본문 스코프 단언(레티놀 서브트리 有 · 비타민C·시카 無)은 F1 픽스(products_controller가 workspace 인자로
# load_dashboard_rows 호출) 전이면 RED다 — 픽스 전엔 리프 풀요청이 전 작업실 루트를 본문에 렌더한다.
class DashboardTreeTest < ActionDispatch::IntegrationTest
  # 멀티레벨 축 + 본문 스코프: 리프 상세 풀요청(레티놀 › 미국 › 30ml/CO0000)은 N+1 없이 그 작업실 서브트리만.
  test "제품 상세 풀요청(멀티레벨)은 N+1 없이 진입 작업실로 스코프된다" do
    sign_in_as(Account.find_by!(email: "kim@cooa.dev")) # 전 제품 가시 → 재루팅 없이 실제 3레벨 트리를 walk
    leaf = Product.find_by!(code: "CO0000")             # 레티놀 › 미국(폴더) › 30ml — 폴더깊이 2 하위 리프
    assert_no_n_plus_one { get product_path(leaf) }
    assert_response :success

    body = response.body
    # 진입 작업실(레티놀) 서브트리는 렌더 — 멀티레벨이 실제로 walk됐음(게이트가 얕은 트리로 위장 안 됨).
    assert_match "레티놀 3% 세럼", body # 진입 작업실 루트(폴더)
    assert_match "CO0000", body         # 레티놀 › 미국(폴더) › 30ml — 폴더깊이 2 하위 리프
    # 타 작업실 루트는 본문에서 부재(F1 회귀 게이트 — 픽스 전엔 전 작업실이 쏟아져 RED). 컨텍스트 사이드바도
    # 그 작업실만 렌더하므로 페이지 전체에서 타 작업실명이 안 나온다.
    assert_no_match "비타민C 브라이트닝 앰플", body
    assert_no_match "시카 수딩 크림", body
  end

  # 멀티루트 축: 한 작업실의 복수 루트 서브트리(/workspaces/:id)도 N+1 없이 렌더. 시드 작업실은 전부 1루트라
  # 2루트 작업실을 테스트 내 생성(multi_root_workspace_test와 동일 픽스처 패턴).
  test "멀티루트 작업실 페이지(/workspaces/:id) 렌더는 N+1을 내지 않음" do
    kim = Account.find_by!(email: "kim@cooa.dev")
    ws = Workspace.create!(name: "합본 게이트 작업실", position: 9)
    root_a = Product.create!(name: "게이트A", kind: "folder", workspace: ws, position: 0)
    root_b = Product.create!(name: "게이트B", kind: "folder", workspace: ws, position: 1)
    Product.create!(name: "에이-일본", parent: root_a, code: "GTA1", country: "JP", position: 0)
    Product.create!(name: "비-미국", parent: root_b, code: "GTB1", country: "US", position: 0)

    sign_in_as(kim)
    assert_no_n_plus_one { get workspace_path(ws) }
    assert_response :success

    # 두 루트가 한 작업실 트리(본문 테이블)에 함께 렌더됐음(멀티루트가 실제로 walk됨 — 게이트 load-bearing).
    table_ids = css_select("main table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
    assert_includes table_ids, root_a.id.to_s
    assert_includes table_ids, root_b.id.to_s
  end
end
