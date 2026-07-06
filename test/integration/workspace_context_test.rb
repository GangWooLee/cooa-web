require "test_helper"

# W2 딥링크: 리소스(버전) 직접 진입 시 사이드바가 그 리소스의 작업실 컨텍스트로 렌더된다 —
# 작업실 헤더 + "모든 작업실" 백링크 + 그 작업실 트리(CO0001) · 타 작업실 트리(CO0100) 부재. 기본=kim(owner).
class WorkspaceContextTest < ActionDispatch::IntegrationTest
  def co0001 = Product.find_by!(code: "CO0001") # 레티놀 › 일본
  def co0100 = Product.find_by!(code: "CO0100") # 비타민C › 중국 (타 작업실)
  def retinol_ws = Product.find_by!(name: "레티놀 3% 세럼").workspace # co0001이 속한 작업실

  test "버전 딥링크 → 사이드바가 그 작업실 컨텍스트(그 트리만 · 백링크)" do
    v = co0001.components.find_by!(component_type: "outer_box").component_versions.find_by!(version_number: 5)
    get component_version_path(v)
    assert_response :success

    assert_match "모든 작업실", css_select("#app-sidebar").to_s, "컨텍스트 백링크 존재"
    assert_select "#app-sidebar [data-node-id='#{co0001.id}']", { minimum: 1 }, "그 작업실 트리 노드 존재"
    assert_select "#app-sidebar [data-node-id='#{co0100.id}']", false, "타 작업실 노드는 부재"

    # 복귀 트리거 고정(X4c): 버전 페이지 main은 셸 트리가 아니라 버전 뷰라 "본문 스코프 단언"의 대상이
    # 아니다(그 커버리지는 dashboard_body_scope_test[통합]·workspace_nav_test[시스템 저니]). 대신 이 페이지가
    # 품고 있는 **복귀 트리거** — 브레드크럼의 제품(리프) 세그먼트가 product_path 풀 내비 링크임 — 을 고정한다.
    # 이 링크를 따라가는 순간이 곧 F1이 재현되던 지점이었다(리프 풀요청 → 셸 본문이 전 작업실 렌더). 링크가
    # 드로어 프레임(부분요청)으로 바뀌면 이 계약이 깨지므로 여기서 못박는다. main 스코프 = 사이드바 트리의
    # 동형 리프 링크(#app-sidebar 내)로 단언이 vacuous하게 충족되는 것을 차단(리뷰 지적 — 본문 쪽만 겨냥).
    assert_select "main a[href='#{product_path(co0001)}']", { minimum: 1 }, "브레드크럼 제품 링크(복귀 트리거)=product_path 풀 내비"
  end

  test "테넌트-와이드 홈(작업실 카드 3 + 멤버 요약)은 N+1 없음" do
    # 카드 빌드(build_workspace_cards)의 배치 구조(리프 수 in-memory·scoped 멤버 1회 조회)를 게이트.
    # choi(카드 1개) 조건의 게이트는 scoped_access_test에 있음 — 여기는 멀티 카드(kim=3루트 전체
    # + 루트별 멤버 아바타 요약)가 load-bearing한 테넌트-와이드 조건(리뷰 지적 보강).
    assert_no_n_plus_one { get root_path }
    assert_response :success
  end

  test "인박스(리소스 없음) → 사이드바 컨텍스트 해제(작업실 목록·트리 미렌더)" do
    # 선행 내비(F3 강화): 작업실(레티놀) 진입으로 컨텍스트를 세운 뒤 인박스로 이동한다. X3(세션 폴백 제거)
    # 전엔 session[:workspace_id] 폴백이 리소스 없는 인박스에서도 직전 작업실 컨텍스트를 되살려 이 해제
    # 단언이 RED였다(버그 재현). X3 후 GREEN — 글로벌 화면(인박스·전사관리)은 항상 컨텍스트 해제.
    get workspace_path(retinol_ws) # 레티놀 작업실 진입 → (X3 전) session[:workspace_id] 세팅
    assert_response :success
    get reviews_path
    assert_response :success

    refute_match "모든 작업실", css_select("#app-sidebar").to_s, "컨텍스트 없음 → 백링크 부재"
    # 컨텍스트 없음 = 작업실 목록(루트만). 트리 리프(CO0001)는 사이드바에 미렌더.
    assert_select "#app-sidebar [data-node-id='#{co0001.id}']", false, "컨텍스트 없음 → 트리 리프 노드 미렌더"
  end
end
