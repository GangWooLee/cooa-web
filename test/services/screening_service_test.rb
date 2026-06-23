require "test_helper"

class ScreeningServiceTest < ActiveSupport::TestCase
  setup do
    @user    = User.create!(name: "RA", role: "ra")
    @product = Product.create!(code: "T1", name: "t", country: "JP", channel: "x", owner: @user)
    @comp    = @product.components.create!(component_type: "outer_box")
    @v       = @comp.component_versions.create!(version_number: 1, current: true)
    @v.ingredients.create!(inci_name: "Retinol", inci_canonical: "RETINOL", declared_pct: 3.0)
    @v.ingredients.create!(inci_name: "Niacinamide", inci_canonical: "NIACINAMIDE")
    @v.label_texts.create!(text_type: "ad", content: "Advanced Anti-Aging Formula")

    IngredientLimit.create!(country: "JP", inci_canonical: "RETINOL", restriction_type: "max_concentration",
                            max_pct: 1.0, category: "leave-on", status: "structured", citation: "jp#x")
    IngredientLimit.create!(country: "JP", inci_canonical: "NIACINAMIDE", restriction_type: "unrestricted",
                            status: "structured", citation: "jp#y")
    AdRiskExpression.create!(country: "JP", keyword_ko: "안티에이징", keyword_native: "anti-aging",
                             risk_level: "critical", citation: "jp#z")
    LabelRequirement.create!(country: "JP", item: "재활용 마크", match_keyword: "재활용|recycl", citation: "jp#r")
  end

  test "retinol over structured JP limit => violation, niacinamide ok, anti-aging unable, missing recycle warning" do
    r = ScreeningService.new(@v, "JP").call
    assert_equal "violation", r.decision, "종합 판정은 위반(violation)이어야 함"

    assert_equal "violation", finding(r, "Retinol")[:decision]
    assert_equal "ok",        finding(r, "Niacinamide")[:decision]
    assert_equal "unable",    r.findings.find { |f| f[:element_type] == "ad" }[:decision]
    assert_equal "warning",   r.findings.find { |f| f[:element_type] == "label" }[:decision]
  end

  test "unverified data downgrades violation to warning + flags human review (보수적 판정)" do
    IngredientLimit.where(country: "JP", inci_canonical: "RETINOL").update_all(status: "unverified")
    r = ScreeningService.new(@v, "JP").call
    retinol = finding(r, "Retinol")
    assert_equal "warning", retinol[:decision]
    assert retinol[:human_review_required]
  end

  test "deterministic: same input yields identical decision" do
    a = ScreeningService.new(@v, "JP").call
    b = ScreeningService.new(@v, "JP").call
    assert_equal a.decision, b.decision
    assert_equal a.findings.map { |f| f[:decision] }, b.findings.map { |f| f[:decision] }
  end

  test "run! persists ScreeningRun + findings with citations" do
    run = ScreeningService.new(@v, "JP").run!(requested_by: @user)
    assert run.persisted?
    assert_equal "violation", run.decision
    assert_operator run.screening_findings.count, :>=, 4
    assert run.screening_findings.find_by(subject: "Retinol").citation.present?
  end

  private

  def finding(result, subject) = result.findings.find { |f| f[:subject] == subject }
end
