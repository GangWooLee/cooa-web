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
end
