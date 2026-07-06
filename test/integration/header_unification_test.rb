require "test_helper"

# D2/D3 헤더·사이드바 통합: 작업실 페이지 헤더 타이틀 = 작업실명(구 하드코드 "데이터 관리")·멤버 어포던스
# 팝오버 트리거(aria-label), 사이드바 = "모든 작업실" 백링크 존치·작업실명 고정 행 삭제(셀렉터 조준).
# 기본 로그인 = kim(owner · 전 트리 가시). 작업실명은 시드 루트 healing으로 루트 제품명과 동일.
class HeaderUnificationTest < ActionDispatch::IntegrationTest
  def retinol = Product.find_by!(name: "레티놀 3% 세럼")

  test "D2 작업실 헤더 타이틀 = 작업실명 · 멤버 어포던스(aria-label) 트리거" do
    get workspace_path(id: retinol.workspace_id)
    assert_response :success

    # 헤더 타이틀 span(20px bold)은 main 안에서 유일(테이블·툴바는 더 작은 글자) → 작업실명으로 조준.
    title = css_select("main span").find { |s| s["class"].to_s.include?("text-[20px]") }
    assert_equal "레티놀 3% 세럼", title&.text&.strip, "헤더 타이틀 = 작업실명(구 '데이터 관리')"

    # 멤버 관리 팝오버 트리거 — 관리자(kim owner)의 접근 이름 = aria-label "멤버 초대·관리".
    assert_select "summary[aria-label='멤버 초대·관리']", { minimum: 1 }, "멤버 어포던스 팝오버 트리거"
  end

  test "D3 사이드바 = '모든 작업실' 백링크 존치 · 작업실명 고정 행(15px bold) 삭제" do
    get workspace_path(id: retinol.workspace_id)
    assert_response :success

    sidebar = css_select("#app-sidebar")
    assert_match "모든 작업실", sidebar.to_s, "컨텍스트 백링크 존치(D3)"
    # 구 작업실명 행 = 백링크 아래 layers + 15px-bold span. 그 시그니처(span.text-[15px].font-bold)는
    # 사이드바에서 유일했다(트리 노드=14px · 검색 input=15px 비-bold) → 삭제 확인 = 해당 span 0건.
    name_rows = sidebar.css("span").select { |s| c = s["class"].to_s; c.include?("text-[15px]") && c.include?("font-bold") }
    assert_empty name_rows, "작업실명 고정 행은 삭제(작업실명은 헤더 타이틀·트리 루트로만 표시)"
  end
end
