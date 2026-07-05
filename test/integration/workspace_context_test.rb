require "test_helper"

# W2 딥링크: 리소스(버전) 직접 진입 시 사이드바가 그 리소스의 작업실 컨텍스트로 렌더된다 —
# 작업실 헤더 + "모든 작업실" 백링크 + 그 작업실 트리(CO0001) · 타 작업실 트리(CO0100) 부재. 기본=kim(owner).
class WorkspaceContextTest < ActionDispatch::IntegrationTest
  def co0001 = Product.find_by!(code: "CO0001") # 레티놀 › 일본
  def co0100 = Product.find_by!(code: "CO0100") # 비타민C › 중국 (타 작업실)

  test "버전 딥링크 → 사이드바가 그 작업실 컨텍스트(그 트리만 · 백링크)" do
    v = co0001.components.find_by!(component_type: "outer_box").component_versions.find_by!(version_number: 5)
    get component_version_path(v)
    assert_response :success

    assert_match "모든 작업실", css_select("#app-sidebar").to_s, "컨텍스트 백링크 존재"
    assert_select "#app-sidebar [data-node-id='#{co0001.id}']", { minimum: 1 }, "그 작업실 트리 노드 존재"
    assert_select "#app-sidebar [data-node-id='#{co0100.id}']", false, "타 작업실 노드는 부재"
  end

  test "테넌트-와이드 홈(작업실 카드 3 + 멤버 요약)은 N+1 없음" do
    # 카드 빌드(build_workspace_cards)의 배치 구조(리프 수 in-memory·scoped 멤버 1회 조회)를 게이트.
    # choi(카드 1개) 조건의 게이트는 scoped_access_test에 있음 — 여기는 멀티 카드(kim=3루트 전체
    # + 루트별 멤버 아바타 요약)가 load-bearing한 테넌트-와이드 조건(리뷰 지적 보강).
    assert_no_n_plus_one { get root_path }
    assert_response :success
  end

  test "인박스(리소스 없음) → 사이드바 컨텍스트 해제(작업실 목록·트리 미렌더)" do
    get reviews_path
    assert_response :success

    refute_match "모든 작업실", css_select("#app-sidebar").to_s, "컨텍스트 없음 → 백링크 부재"
    # 컨텍스트 없음 = 작업실 목록(루트만). 트리 리프(CO0001)는 사이드바에 미렌더.
    assert_select "#app-sidebar [data-node-id='#{co0001.id}']", false, "컨텍스트 없음 → 트리 리프 노드 미렌더"
  end
end
