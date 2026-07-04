require "test_helper"

# Stage 2 (D3, 시나리오③-절반): 최디자(choi)는 CO0200 제품 하나에만 external_collaborator 스코프를
# 가진다. 사이드바·대시보드에 CO0200만 보이고(조상 브랜드는 노드로 렌더 안 됨), 타 제품은 접근 차단되며,
# 리뷰 인박스 Segment B(적격자 전용)는 렌더되지 않는다. 기존 4페르소나(tenant-wide)는 전권 무회귀.
class ScopedAccessTest < ActionDispatch::IntegrationTest
  def choi = Account.find_by!(email: "choi@partner.example")
  def co0200 = Product.find_by!(code: "CO0200")
  def co0001 = Product.find_by!(code: "CO0001")
  def cica = Product.find_by!(name: "시카 수딩 크림") # CO0200의 (비가시) 조상 브랜드 루트

  test "스코프 계정의 대시보드는 부여 제품만 보이고 타 브랜드·조상 노드는 렌더되지 않음" do
    sign_in_as(choi)
    get root_path
    assert_response :success
    body = response.body
    assert_match(/data-node-id="#{co0200.id}"/, body, "CO0200이 노드로 보여야 함")
    assert_match "CO0200", body
    # 다른 브랜드(부여 무관)는 완전 부재
    assert_no_match "레티놀 3% 세럼", body
    assert_no_match "비타민C 브라이트닝 앰플", body
    # 조상 브랜드(CO0200의 부모 cica)는 트리 노드로 렌더되지 않음 = 재루팅으로 브랜드명 유출 차단
    assert_no_match(/data-node-id="#{cica.id}"/, body, "비가시 조상은 노드로 렌더되면 안 됨")
    # 조상 브랜드명 문자열 자체가 응답에 없어야 함(data-node-path 속성 등 어디에도) = D3 브랜드명 유출 차단.
    assert_no_match cica.name, body, "권한 없는 상위 브랜드명이 텍스트/속성 어디에도 노출되면 안 됨"
  end

  test "스코프 계정의 제품 상세 드로어 경로에 권한 없는 상위 브랜드명이 노출되지 않음" do
    sign_in_as(choi)
    get product_path(co0200) # 풀 요청 → 대시보드 셸 + 드로어(경로 = node_path_label)
    assert_response :success
    body = response.body
    assert_match "미국", body, "부여 제품명(CO0200=미국)은 보여야 함"
    # 드로어 "경로" 브레드크럼·data-node-path 어디에도 상위 브랜드명(cica) 문자열 부재.
    assert_no_match cica.name, body, "드로어 경로/속성에 권한 없는 상위 브랜드명이 노출되면 안 됨"
  end

  test "스코프 계정은 부여 제품은 열람하고 타 제품 진입은 차단됨" do
    sign_in_as(choi)

    get product_path(co0200) # 부여 제품 — 열람 가능
    assert_response :success

    get product_path(co0001) # 타 제품 — GET html deny = root로 리다이렉트(콘텐츠 미노출)
    assert_redirected_to root_path

    other_version = co0001.components.first.component_versions.first
    get component_version_path(other_version) # 타 제품의 버전도 차단
    assert_redirected_to root_path

    # 변이(non-GET) deny는 403 — 타 제품에 구성요소 추가 시도
    post product_components_path(co0001)
    assert_response :forbidden
  end

  test "스코프 계정의 리뷰 인박스에는 Segment B(미배정)가 렌더되지 않음 — 비적격" do
    # 미배정 pending 리뷰를 하나 만든다(제출자 kim, 리뷰어 0명 = Segment B 후보).
    kim = User.find_by!(email: "kim@cooa.dev")
    v = co0001.components.first.component_versions.first
    ApprovalRequest.submit_for!(v, submitter_id: kim.id, reviewer_ids: [])

    sign_in_as(choi) # external_collaborator ∉ 적격(owner/approver) → Segment B 스킵
    get reviews_path
    assert_response :success
    assert_no_match "맡을 수 있는 리뷰", response.body # Segment B 섹션 헤더 미노출

    # 대조: tenant-wide 적격자(lee)는 동일 미배정 리뷰를 Segment B에서 봄(교집합=no-op·무회귀).
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    get reviews_path
    assert_response :success
    assert_match "CO0001", response.body
  end

  test "기존 tenant-wide 페르소나(kim)는 전 제품 무회귀" do
    sign_in_as(Account.find_by!(email: "kim@cooa.dev"))
    get root_path
    assert_response :success
    assert_match "레티놀 3% 세럼", response.body
    assert_match "비타민C 브라이트닝 앰플", response.body
    assert_match "시카 수딩 크림", response.body
  end

  test "스코프 계정 대시보드는 N+1을 내지 않음(critical path)" do
    sign_in_as(choi)
    assert_no_n_plus_one { get root_path }
    assert_response :success
  end
end
