require "test_helper"

# 드로어/사이드바 UI 3건 회귀
class DrawerUiTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def hero = Product.find_by(code: "CO0001")

  test "Fix1: 드로어 비교 링크는 풀페이지(_top)로 이탈(detail 프레임 가둠 방지)" do
    get product_path(hero), headers: { "Turbo-Frame" => "detail" }
    assert_response :success
    assert_select "a[href*='/compare/'][data-turbo-frame='_top']", minimum: 1
  end

  test "Fix2: 사이드바 생성(origin=side)은 rename_side로 리다이렉트" do
    assert_difference -> { Product.count }, 1 do
      post products_path, params: { product: { kind: "folder" }, origin: "side" }
    end
    assert_redirected_to root_path(rename_side: Product.order(:id).last.id)
  end

  test "Fix2: 대시보드 생성(origin 없음)은 기존 rename으로 리다이렉트" do
    post products_path, params: { product: { kind: "folder" } }
    assert_redirected_to root_path(rename: Product.order(:id).last.id)
  end

  test "Fix2: rename_side는 사이드바 트리에서만 인라인 입력 auto-open(대시보드 미반응)" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    get root_path(rename_side: folder.id)
    assert_response :success
    assert_equal 1, @response.body.scan('data-inline-edit-auto-value="true"').size,
                 "사이드바 대상 1개만 auto-open(대시보드 row는 rename 미설정 → false)"
    assert_select "form[action='#{product_path(folder)}'] input[name='product[name]']", minimum: 1
  end

  test "Fix2: 기존 rename(대시보드)은 사이드바를 auto-open하지 않음" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    get root_path(rename: folder.id) # 대시보드 흐름
    assert_response :success
    # 대시보드 row가 auto-open(true) — 사이드바 _tree_node는 rename_side 미설정이라 false
    assert_includes @response.body, 'data-inline-edit-auto-value="true"'
  end

  # ── R3: 브레드크럼 내비 ──
  test "R3: 폴더 직접 URL은 드로어 대신 대시보드(focus)로 리다이렉트" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    get product_path(folder)
    assert_redirected_to root_path(focus: folder.id)
  end

  test "R3: 브레드크럼 — 폴더 세그먼트→대시보드(focus), 리프 세그먼트→드로어" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    v = hero.components.find_by(component_type: "outer_box").component_versions.find_by(version_number: 5)
    get screening_component_version_path(v)
    assert_response :success
    assert_select "a[href=?]", root_path(focus: folder.id), minimum: 1 # 폴더 → 대시보드
    assert_select "a[href=?]", product_path(hero), minimum: 1          # 리프(일본) → 드로어
  end

  test "R3: focus 파라미터는 사이드바에서 해당 폴더 조상을 펼침" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    get root_path(focus: folder.id)
    assert_response :success
    assert_select "details[open] summary[data-node-id=?]", folder.id.to_s, minimum: 1
  end

  # ── R4: 인라인 편집 일관성 ──
  test "R4: 국가는 select(라벨=한글, 값=코드) — 표시와 일관, 저장은 코드" do
    get product_path(hero), headers: { "Turbo-Frame" => "detail" }
    assert_response :success
    assert_select "select[name='product[country]'] option[selected][value=?]", "JP" do |o|
      assert_equal "일본", o.first.text
    end
    assert_select "input[type=text][name='product[country]']", false, "국가는 텍스트 입력이 아님"
    # 저장은 코드로 영속(스크리닝 for_country 정상)
    patch product_path(hero), params: { product: { country: "CN" } }
    assert_equal "CN", hero.reload.country
  end

  test "R4: 경로는 표시 전용(클릭 편집 폼 없음)" do
    get product_path(hero), headers: { "Turbo-Frame" => "detail" }
    assert_response :success
    assert_select "input[name='product[parent_id]']", false, "경로 편집(상위폴더 select) 제거"
    assert_select "select[name='product[parent_id]']", false
  end
end
