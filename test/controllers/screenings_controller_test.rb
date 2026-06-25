require "test_helper"

class ScreeningsControllerTest < ActionDispatch::IntegrationTest
  setup { Rails.application.load_seed }

  def hero_version
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box").component_versions.detect(&:current)
  end

  test "run_screening → ran=1 리다이렉트(스캔 애니메이션 트리거)" do
    v = hero_version
    post run_screening_component_version_path(v)
    assert_redirected_to screening_component_version_path(v, ran: 1)
  end

  test "결과: '적합'(ok)은 리스트에서 제외 · 위반만 렌더 + 출처/스캔 마크업" do
    v = hero_version
    post run_screening_component_version_path(v)
    run = v.screening_runs.last
    assert run.screening_findings.decision_ok.any?, "ok finding 존재(시드 확인)"
    issues = run.screening_findings.where.not(decision: "ok").count
    assert issues.positive?, "위반 존재"

    get screening_component_version_path(v, ran: 1)
    assert_response :success
    body = @response.body
    rendered = body.scan(/data-screening-target="finding"/).size
    assert_equal issues, rendered, "ok 제외하고 위반/주의만 렌더"
    assert_includes body, "출처", "출처 라벨 명시"
    assert_includes body, 'data-screening-target="scanner"', "스캔 오버레이"
    assert_includes body, "opacity-0 blur-[2px]", "결과 초기 숨김(순차 reveal 대상)"
  end

  test "국가 미지정이면 run_screening 차단(거짓 '적합' 방지) + 화면 안내" do
    v = hero_version
    v.product.update!(country: nil) # 국가 비움
    assert_no_difference -> { ScreeningRun.count } do
      post run_screening_component_version_path(v)
    end
    assert_redirected_to screening_component_version_path(v) # ran=1 아님(실행 안 됨)
    get screening_component_version_path(v)
    assert_includes @response.body, "국가가 지정되지 않아", "실행 불가 안내 배너"
  end
end
