require "test_helper"

class TabsControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  test "show가 세션 탭에 push (중복제거·최신순)" do
    a = Product.find_by(code: "CO0001")
    b = Product.find_by(code: "CO0100")
    get product_path(a)
    get product_path(b)
    get product_path(a) # 재방문 → 맨 앞으로
    assert_equal [a.id, b.id], session[:open_tabs], "최신순 + 중복제거"
  end

  test "코드 없는 폴더는 탭에 안 들어감" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    get product_path(folder)
    assert_not (session[:open_tabs] || []).include?(folder.id)
  end

  test "탭 닫기 — DELETE /tabs/:id" do
    a = Product.find_by(code: "CO0001")
    get product_path(a)
    assert_includes session[:open_tabs], a.id
    delete tab_path(a)
    assert_not (session[:open_tabs] || []).include?(a.id)
  end

  test "삭제된 제품은 탭 렌더에서 제외(오류 없음)" do
    a = Product.find_by(code: "CO0001")
    get product_path(a)
    a.destroy
    get root_path # set_nav 재계산 — 삭제된 id 제외하고 정상 렌더
    assert_response :success
  end
end
