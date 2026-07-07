require "test_helper"

class ScreeningServiceTest < ActiveSupport::TestCase
  setup do
    # 전역 규제 KB(비-RLS)는 committed_state_cleanup 범위 밖 — 비트랜잭션 RLS 스위트가 커밋한 시드 잔여물이
    # 남으면 아래 bare create!가 UniqueViolation(예: JP/RETINOL)·판정 오염을 일으킨다(W1·D2 워커 2회 실측).
    # 트랜잭션 내 선삭제로 결정론 격리 — 테스트 롤백이 원복하므로 공유 커밋 상태는 불변.
    [ IngredientLimit, AdRiskExpression, LabelRequirement ].each { |m| m.where(country: "JP").delete_all }
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

  test "banned 성분 => violation/Critical/96 (가장 치명적 분기 — 회귀 방지)" do
    @v.ingredients.create!(inci_name: "Mercury", inci_canonical: "MERCURY")
    IngredientLimit.create!(country: "JP", inci_canonical: "MERCURY", restriction_type: "banned",
                            category: "all", status: "structured", citation: "jp#banned")
    r = ScreeningService.new(@v, "JP").call
    hg = finding(r, "Mercury")
    assert_equal "violation", hg[:decision]
    assert_equal "Critical", hg[:severity]
    assert_equal 96, hg[:confidence]
    assert_equal "violation", r.decision
  end

  test "capped 성분인데 declared_pct 미상 => warning + human_review (적합 단정 금지)" do
    @v.ingredients.create!(inci_name: "Squalane", inci_canonical: "SQUALANE") # declared_pct 없음
    IngredientLimit.create!(country: "JP", inci_canonical: "SQUALANE", restriction_type: "max_concentration",
                            max_pct: 40.0, category: "leave-on", status: "structured", citation: "jp#sq")
    r = ScreeningService.new(@v, "JP").call
    sq = finding(r, "Squalane")
    assert_equal "warning", sq[:decision], "한도 규제+농도 미상은 적합이 아니라 주의여야 함"
    assert sq[:human_review_required]
  end

  test "종합판정: 실재 '주의'가 미결정 '판단불가'에 가려지지 않음" do
    assert_equal "warning",   ScreeningFinding.worst_decision(%w[ok unable warning])
    assert_equal "violation", ScreeningFinding.worst_decision(%w[warning unable violation])
    assert_equal "unable",    ScreeningFinding.worst_decision(%w[ok unable])
    assert_equal "ok",        ScreeningFinding.worst_decision([])
  end

  test "박스: 히어로 전개도(box_v5)만 좌표 부여, 그 외 아트워크는 미부여(틀린 박스 방지)" do
    r1 = ScreeningService.new(@v, "JP").call # @v: image_name 없음 → 비히어로
    assert r1.findings.any? { |f| f[:decision] != "ok" }, "위반 finding 존재"
    assert r1.findings.none? { |f| f[:box_x].present? }, "비히어로 아트워크엔 박스 없음"
    @v.update_column(:image_name, "cooa/box_v5.jpg")
    r2 = ScreeningService.new(@v, "JP").call
    assert r2.findings.any? { |f| f[:subject].to_s.upcase == "RETINOL" && f[:box_x].present? }, "히어로엔 RETINOL 박스"
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
