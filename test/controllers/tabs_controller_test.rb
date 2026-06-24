require "test_helper"

class TabsControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def hero_version
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box").component_versions.detect(&:current)
  end

  test "제품 show → 세션 탭에 키 push (중복제거·최신순)" do
    a = Product.find_by(code: "CO0001")
    b = Product.find_by(code: "CO0100")
    get product_path(a)
    get product_path(b)
    get product_path(a) # 재방문 → 맨 앞으로
    assert_equal ["p-#{a.id}", "p-#{b.id}"], session[:open_tabs], "최신순 + 중복제거"
  end

  test "버전 보기 / 스크리닝도 히스토리에 기록(v-/s- 키)" do
    v = hero_version
    get component_version_path(v)
    assert_includes session[:open_tabs], "v-#{v.id}", "버전 보기 → v- 탭"
    get screening_component_version_path(v)
    assert_includes session[:open_tabs], "s-#{v.id}", "스크리닝 → s- 탭"
    # 헤더에 버전/스크리닝 탭 렌더
    get root_path
    assert_response :success
    assert_includes @response.body, "스크리닝"
    assert_includes @response.body, v.component.display_name
  end

  test "코드 없는 폴더는 탭에 안 들어감" do
    folder = Product.find_by(name: "레티놀 3% 세럼")
    get product_path(folder)
    assert_not (session[:open_tabs] || []).include?("p-#{folder.id}")
  end

  test "탭 닫기 — DELETE /tabs/:key" do
    a = Product.find_by(code: "CO0001")
    v = hero_version
    get product_path(a)
    get component_version_path(v)
    assert_includes session[:open_tabs], "p-#{a.id}"
    delete tab_path("v-#{v.id}")
    assert_not (session[:open_tabs] || []).include?("v-#{v.id}"), "v 탭만 제거"
    assert_includes session[:open_tabs], "p-#{a.id}", "다른 탭 유지"
  end

  test "삭제된 대상은 탭 렌더에서 제외(오류 없음)" do
    a = Product.find_by(code: "CO0001")
    get product_path(a)
    a.destroy
    get root_path # set_nav 재계산 — 삭제된 대상 제외하고 정상 렌더
    assert_response :success
  end
end
