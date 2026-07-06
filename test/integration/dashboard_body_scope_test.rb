require "test_helper"

# 컨텍스트-본문 정합(F1 회귀 게이트): 리소스(리프) 풀요청 시 대시보드 셸의 **본문 트리 테이블**이 그 리소스의
# 작업실로 스코프돼야 한다 — 사이드바만이 아니라 본문도. 본문 셀렉터 = <main> 안 트리 테이블
# tbody tr[data-node-id]이고, 사이드바(#app-sidebar)와 반드시 구분한다: 사이드바는 F1 이전에도 @product →
# workspace_of_node로 올바르게 스코프됐고, 실제 버그는 **본문 셸**이 전 작업실 트리를 렌더하던 분열이었다.
# 근본원인 = products_controller가 load_dashboard_rows를 workspace 인자 없이 호출 → @rows가 가시 전체.
# 기본 로그인 = kim(tenant-wide · 전 작업실 가시) — 스코프 결함이 가장 드러나는 신원(스코프 계정은 애초에
# 타 작업실이 가시집합 밖이라 결함이 잠복). X1(products_controller에 workspace 스코프 주입) 전엔 RED.
class DashboardBodyScopeTest < ActionDispatch::IntegrationTest
  def co0001  = Product.find_by!(code: "CO0001")                # 레티놀 › 일본(리프)
  def retinol = Product.find_by!(name: "레티놀 3% 세럼")         # 진입 작업실 루트(레티놀)
  def vitc    = Product.find_by!(name: "비타민C 브라이트닝 앰플") # 타 작업실 루트
  def cica    = Product.find_by!(name: "시카 수딩 크림")         # 타 작업실 루트

  # 본문 트리 행 id — <main> 안 트리 테이블만(사이드바 #app-sidebar는 <main> 밖이라 자동 제외).
  def body_node_ids
    css_select("main table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
  end

  test "리프 풀요청(product_path)의 본문 트리는 진입 작업실 서브트리만(타 작업실 부재)" do
    get product_path(co0001) # 레티놀 › 일본 리프 풀페이지(셸 + 드로어)
    assert_response :success

    ids = body_node_ids
    assert_includes ids, retinol.id.to_s, "진입 작업실 루트(레티놀)는 본문에 존재"
    assert_includes ids, co0001.id.to_s,  "진입 작업실 리프(일본/CO0001)는 본문에 존재"
    refute_includes ids, vitc.id.to_s, "타 작업실 루트(비타민C)는 본문에 부재(F1 회귀 게이트)"
    refute_includes ids, cica.id.to_s, "타 작업실 루트(시카)는 본문에 부재(F1 회귀 게이트)"
  end

  # 정상 대조군(X4d): root_path(focus: 리프)는 dashboard#index가 이미 그 노드의 작업실로 스코프
  # (resolve_index_workspace → load_dashboard_rows(workspace:)) → F1 이전에도 올발랐다. 리프 상세 경로가
  # 이 focus 경로와 동일한 본문 스코프를 갖게 하는 것이 X1의 목표 — 같은 기대를 병치해 회귀를 격리한다.
  test "root_path(focus: 리프)의 본문 트리는 그 작업실만(정상 대조군)" do
    get root_path(focus: co0001.id)
    assert_response :success

    ids = body_node_ids
    assert_includes ids, retinol.id.to_s
    assert_includes ids, co0001.id.to_s
    refute_includes ids, vitc.id.to_s
    refute_includes ids, cica.id.to_s
  end
end
