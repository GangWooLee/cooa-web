require "test_helper"

# Stage 4 T4 (/brands/:id 실구현 — 팀 페이지): dashboard#index가 params[:id]면 그 브랜드(루트 제품)
# 서브트리로 트리를 좁히고, 브랜드명 헤더 + 그 브랜드 체인의 스코프 멤버 요약을 렌더한다. 비가시 브랜드
# (스코프 계정의 타 브랜드) 접근은 기존 Scope 동작대로 redirect(같은 테넌트·비가시) / 404(미존재).
class BrandsPageTest < ActionDispatch::IntegrationTest
  def retinol = Product.find_by!(name: "레티놀 3% 세럼")
  def sica    = Product.find_by!(name: "시카 수딩 크림")
  def vitc    = Product.find_by!(name: "비타민C 브라이트닝 앰플")

  test "브랜드 페이지는 그 서브트리만 렌더 · 타 브랜드 노드 부재" do
    get workspace_path(id: retinol.workspace_id)
    assert_response :success
    # 메인 트리(테이블) 행 id — 사이드바(전체 브랜드 트리)와 구분해 dashboard @rows만 검증.
    table_ids = css_select("table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
    [ retinol, Product.find_by!(code: "CO0000"), Product.find_by!(code: "CO0001") ].each do |p|
      assert_includes table_ids, p.id.to_s, "서브트리 노드(#{p.name})는 메인 트리에 렌더"
    end
    assert_not_includes table_ids, sica.id.to_s, "타 브랜드 루트는 메인 트리 밖"
    assert_not_includes table_ids, Product.find_by!(code: "CO0200").id.to_s, "타 브랜드 SKU는 메인 트리 밖"
  end

  test "멤버 요약: 스코프 grant 보유자 배지(시카=최디자) · 스코프 없는 브랜드는 안내문" do
    get workspace_path(id: sica.workspace_id) # 시카 서브트리엔 choi(external @ CO0200)
    assert_response :success
    assert_match "작업실", response.body
    assert_match "최디자", response.body, "그 브랜드 체인 스코프 멤버는 요약에 표시"

    get workspace_path(id: retinol.workspace_id) # 레티놀엔 스코프 grant 없음
    assert_response :success
    assert_match "지정된 멤버가 없습니다", response.body
  end

  test "비타민C 브랜드 페이지 멤버 요약에 정브랜(brand_admin scoped)" do
    get workspace_path(id: vitc.workspace_id)
    assert_response :success
    assert_match "정브랜", response.body
  end

  test "관리 권한자(kim owner)는 작업실 인라인 멤버 관리 패널 노출" do
    get workspace_path(id: retinol.workspace_id) # 기본 로그인 = kim(owner)
    # 구 "멤버 관리" 이탈 링크 → 작업실 페이지 인라인 패널(_workspace_members). 초대 폼 헤딩으로 단언.
    assert_match "이 작업실에 초대", response.body
  end

  test "비가시 브랜드(스코프 계정의 타 브랜드) 접근 → root redirect(콘텐츠 미노출)" do
    sign_in_as(Account.find_by!(email: "choi@partner.example")) # CO0200만 스코프 — 레티놀 비가시
    get workspace_path(id: retinol.workspace_id)
    assert_redirected_to root_path
  end

  test "미존재 브랜드 id → 404" do
    get workspace_path(id: 999_999)
    assert_response :not_found
  end

  test "브랜드 페이지 렌더는 N+1 없음(critical path)" do
    assert_no_n_plus_one { get workspace_path(id: retinol.workspace_id) }
    assert_response :success
  end
end
