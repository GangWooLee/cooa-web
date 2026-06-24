require "test_helper"

# 데모 4개 화면 + 인터랙션 end-to-end (시드 데이터 기반)
class DemoFlowsTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def hero_v(n)
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: n)
  end

  test "① 대시보드 렌더 (제품 트리)" do
    get root_path
    assert_response :success
    assert_match "데이터 관리", response.body
    assert_match "레티놀 3% 세럼", response.body
    assert_match "CO0001", response.body
    assert_no_match(/BRAND/, response.body)
  end

  test "② 제품 상세 허브 렌더" do
    get product_path(Product.find_by(code: "CO0001"))
    assert_response :success
    assert_match "구성요소", response.body
    assert_match "변경사유", response.body
  end

  test "④ 스크리닝 실행 + RA 승인" do
    v = hero_v(5)
    assert_difference -> { v.screening_runs.count }, 1 do
      post run_screening_component_version_path(v)
    end
    assert_redirected_to screening_component_version_path(v, ran: 1) # 스캔 애니메이션 트리거

    post approve_screening_component_version_path(v)
    assert v.screening_runs.order(:created_at).last.approved?
  end

  test "③ 비교 렌더 + 어노테이션 코멘트/해소/생성" do
    from = hero_v(5)
    to   = hero_v(6)

    get comparison_path(from_id: from.id, to_id: to.id)
    assert_response :success
    assert_match "피드백", response.body

    ann = from.annotations.open.first # 미해결(DMAH)
    assert_difference -> { ann.comments.count }, 1 do
      post annotation_comments_path(ann), params: { body: "추가 코멘트" }
    end

    patch resolve_annotation_path(ann), params: { resolved_in_version_id: to.id }
    assert ann.reload.resolved?, "반영확인 시 resolved 되어야 함"

    assert_difference -> { to.annotations.count }, 1 do
      post component_version_annotations_path(to),
           params: { box_x: 10, box_y: 10, box_w: 8, box_h: 5, category: "디자인", body: "새 피드백" }
    end
  end

  test "스크리닝 finding 박스 좌표 부여" do
    run = hero_v(5).screening_runs.order(:created_at).last
    assert run.screening_findings.any?(&:boxed?), "박스 지정된 finding이 있어야 함"
  end

  test "US 대조군 스크리닝은 적합" do
    us = Product.find_by(code: "CO0000").components.find_by(component_type: "outer_box")
                .component_versions.find_by(version_number: 5)
    run = us.screening_runs.order(:created_at).last
    assert_equal "ok", run.decision
  end
end
