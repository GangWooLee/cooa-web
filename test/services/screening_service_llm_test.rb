require "test_helper"

# ScreeningService × LlmScreeningJudge 통합 — judge를 스텁해 하이브리드 경로가 종합 판정·summary·영속에
# 정합하게 반영되는지 검증한다(실 API 무호출). 키 없는 기본 경로(무변경)도 확인.
class ScreeningServiceLlmTest < ActiveSupport::TestCase
  setup do
    @prev_key = ENV.delete("ANTHROPIC_API_KEY") # 기본 경로를 결정적으로 키-없음으로 고정
    [ IngredientLimit, AdRiskExpression, LabelRequirement ].each { |m| m.where(country: "JP").delete_all }
    @user    = User.create!(name: "RA", role: "ra")
    @product = Product.create!(code: "TL1", name: "t", country: "JP", channel: "x", owner: @user)
    @comp    = @product.components.create!(component_type: "outer_box")
    @v       = @comp.component_versions.create!(version_number: 1, current: true)
    @v.ingredients.create!(inci_name: "Niacinamide", inci_canonical: "NIACINAMIDE")
    @v.label_texts.create!(text_type: "ad", content: "Advanced Anti-Aging Formula")
    # 룰-only 종합 판정이 unable이 되도록: 성분은 ok, 광고만 critical(=unable), 미충족 라벨 요구는 없음.
    IngredientLimit.create!(country: "JP", inci_canonical: "NIACINAMIDE", restriction_type: "unrestricted",
                            status: "structured", citation: "jp#niac")
    AdRiskExpression.create!(country: "JP", keyword_ko: "안티에이징", keyword_native: "anti-aging",
                             risk_level: "critical", fact_id: "jp-ad1", citation: "jp#ad")
  end

  teardown { ENV["ANTHROPIC_API_KEY"] = @prev_key unless @prev_key.nil? }

  test "룰-only(키 없음): ad unable · 종합 unable · summary에 AI 표기 없음" do
    r = ScreeningService.new(@v, "JP").call
    assert_equal "unable", r.findings.find { |f| f[:element_type] == "ad" }[:decision]
    assert_equal "unable", r.decision
    refute_includes r.summary, "AI 보조판정"
  end

  test "judge 스텁 unable→violation 승격: run 판정 변화 + summary 표기 + 영속 반영" do
    stub_refine(method(:promote_ad_to_violation)) do
      run = ScreeningService.new(@v, "JP").run!(requested_by: @user)
      assert_equal "violation", run.decision, "AI 승격이 종합 판정에 반영돼야 함"
      assert_includes run.summary, "(AI 보조판정 1건)"
      ad = run.screening_findings.find_by(element_type: "ad")
      assert_equal "violation", ad.decision
      assert_includes ad.issue_description, "AI 보조판정:"
      assert ad.human_review_required
      assert_equal "jp#ad", ad.citation
    end
  end

  test "run!은 transient :ai_refined 키를 영속 전 제거한다(UnknownAttribute 방지)" do
    stub_refine(->(findings, **) { findings.map { |f| f.merge(ai_refined: true) } }) do
      assert_nothing_raised { ScreeningService.new(@v, "JP").run!(requested_by: @user) }
    end
  end

  private

  # minitest/mock가 이 번들(minitest 6)에 없어 클래스 메서드를 임시 교체·복원하는 최소 헬퍼(인자 전달·ensure 복원).
  def stub_refine(replacement)
    original = LlmScreeningJudge.method(:refine)
    LlmScreeningJudge.singleton_class.send(:define_method, :refine) { |*a, **k| replacement.call(*a, **k) }
    yield
  ensure
    LlmScreeningJudge.singleton_class.send(:define_method, :refine, original)
  end

  # 광고 unable finding을 violation으로 승격(인용 바인딩·RA검토 유지·AI 마킹) — 실 judge의 성공 경로 모사.
  def promote_ad_to_violation(findings, version:, country:)
    findings.map do |f|
      next f unless f[:element_type] == "ad" && f[:decision] == "unable"

      f.merge(decision: "violation", citation: "jp#ad", human_review_required: true, ai_refined: true,
              issue_description: "#{f[:issue_description]}\nAI 보조판정: 의약품적 효능 표현으로 판단.")
    end
  end
end
