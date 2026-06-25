require "test_helper"

class TabsControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def hero_versions
    comp = Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
    comp.component_versions.sort_by(&:version_number)
  end

  test "드로어(제품 show)는 히스토리에 기록하지 않음" do
    a = Product.find_by(code: "CO0001")
    get product_path(a)
    assert_empty session[:open_tabs].to_a, "드로어 진입은 탭 안 만듦"
  end

  test "풀페이지 작업(버전·스크리닝·비교)만 기록 + 쌓인 순서 유지(재방문 무이동)" do
    from, to = hero_versions.first(2)
    get component_version_path(from)        # v
    get screening_component_version_path(from) # s
    get comparison_path(from_id: from.id, to_id: to.id) # c
    get component_version_path(from)        # 재방문 → 무이동
    assert_equal ["v-#{from.id}", "s-#{from.id}", "c-#{from.id}-#{to.id}"], session[:open_tabs],
                 "쌓인 순서 유지, 재방문 시 재정렬·중복 없음"
    # 헤더 렌더
    get root_path
    assert_response :success
    assert_includes @response.body, "스크리닝"
    assert_includes @response.body, from.component.display_name
  end

  test "탭 닫기 — DELETE /tabs/:key(해당 키만 제거)" do
    from, to = hero_versions.first(2)
    get component_version_path(from)
    get screening_component_version_path(from)
    delete tab_path("v-#{from.id}")
    assert_not (session[:open_tabs] || []).include?("v-#{from.id}"), "v 탭만 제거"
    assert_includes session[:open_tabs], "s-#{from.id}", "다른 탭 유지"
  end

  test "삭제된 대상은 탭 렌더에서 제외(오류 없음)" do
    v = hero_versions.first
    get component_version_path(v)
    v.destroy
    get root_path # set_nav 재계산 — 삭제된 대상 제외하고 정상 렌더
    assert_response :success
  end
end
