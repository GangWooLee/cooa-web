require "test_helper"

# LlmScreeningJudge 단위 테스트 — HTTP 클라이언트를 주입해 실제 API 호출 없이 검증한다.
#  경계 선별 · 인용 바인딩 기각 · decision 전이 가드 · human_review 유지 · confidence 클램프 ·
#  실패 시 fail-open · available? false 무호출 · 사용량 메타 노출.
class LlmScreeningJudgeTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  # post(url:, headers:, body:) — 실 클라이언트와 동일 시그니처. 호출 캡처·에러 주입 지원.
  class FakeClient
    attr_reader :calls, :last_body

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @calls = 0
    end

    def post(url:, headers:, body:)
      @calls += 1
      @last_body = body
      raise @error if @error
      @response
    end
  end

  setup do
    @prev_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "test-key" # available? true (주입 클라이언트라 실호출 없음)
    [ IngredientLimit, AdRiskExpression, LabelRequirement ].each { |m| m.where(country: "JP").delete_all }
    AdRiskExpression.create!(country: "JP", keyword_ko: "안티에이징", keyword_native: "anti-aging",
                             risk_level: "critical", fact_id: "jp-ad1", citation: "JP-AD-CIT")
    @version = fake_version("ANTI-AGING FORMULA")
  end

  teardown do
    @prev_key.nil? ? ENV.delete("ANTHROPIC_API_KEY") : ENV["ANTHROPIC_API_KEY"] = @prev_key
  end

  test "available? false → 무호출·무변경" do
    ENV.delete("ANTHROPIC_API_KEY")
    client = FakeClient.new(error: RuntimeError.new("호출되면 안 됨"))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    assert_equal 0, client.calls
    assert_equal "unable", out.first[:decision]
  end

  test "테스트 환경 + 주입 클라이언트 없음 → 무변경(실키가 있어도 스위트가 실 API를 치지 않음)" do
    out = LlmScreeningJudge.new.refine([ ad_finding ], version: @version, country: "JP")
    assert_equal "unable", out.first[:decision]
    refute out.first[:ai_refined]
  end

  test "country != JP → 무호출·무변경" do
    client = FakeClient.new(error: RuntimeError.new("nope"))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "CN")
    assert_equal 0, client.calls
    assert_equal "unable", out.first[:decision]
  end

  test "경계 사례 0건 → 무호출·무변경" do
    client = FakeClient.new(error: RuntimeError.new("nope"))
    findings = [ ad_finding(decision: "violation", human_review_required: false) ]
    out = LlmScreeningJudge.new(http_client: client).refine(findings, version: @version, country: "JP")
    assert_equal 0, client.calls
    assert_equal "violation", out.first[:decision]
  end

  test "경계 선별 — unable·RA주의만 프롬프트에 포함(violation·일반 주의는 제외)" do
    findings = [
      ad_finding(decision: "unable", subject: "A"),
      ad_finding(decision: "violation", subject: "B", human_review_required: false),
      ad_finding(decision: "warning", subject: "C", human_review_required: false),
      ad_finding(decision: "warning", subject: "D", human_review_required: true)
    ]
    client = FakeClient.new(response: api_response([]))
    LlmScreeningJudge.new(http_client: client).refine(findings, version: @version, country: "JP")
    prompt = JSON.parse(client.last_body).dig("messages", 0, "content")
    assert_includes prompt, "주제=\"A\""
    assert_includes prompt, "주제=\"D\""
    refute_includes prompt, "주제=\"B\""
    refute_includes prompt, "주제=\"C\""
  end

  test "unable→violation 승격 + 인용 바인딩 + human_review 유지 + confidence 상한 클램프" do
    verdicts = [ verdict(decision: "violation", citation_fact_id: "jp-ad1", confidence: 99,
                         rationale_ko: "의약품적 효능 표현으로 판단.") ]
    client = FakeClient.new(response: api_response(verdicts))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    f = out.first
    assert_equal "violation", f[:decision]
    assert_includes f[:issue_description], "AI 보조판정: 의약품적 효능 표현으로 판단."
    assert_equal "JP-AD-CIT", f[:citation], "citation은 바인딩된 fact의 것으로 교체"
    assert_equal 95, f[:confidence], "99 → 95 클램프"
    assert f[:human_review_required], "AI 판정이라도 RA 검토 유지"
    assert f[:ai_refined]
  end

  test "unable→ok + confidence 하한 클램프(55), ok여도 RA 검토 유지" do
    verdicts = [ verdict(decision: "ok", citation_fact_id: "jp-ad1", confidence: 10, rationale_ko: "문제 없음.") ]
    client = FakeClient.new(response: api_response(verdicts))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    assert_equal "ok", out.first[:decision]
    assert_equal 55, out.first[:confidence]
    assert out.first[:human_review_required]
  end

  test "citation_fact_id가 fact 집합 밖(환각) → 판정 폐기, 룰 판정 유지" do
    verdicts = [ verdict(decision: "violation", citation_fact_id: "hallucinated-999", confidence: 90) ]
    client = FakeClient.new(response: api_response(verdicts))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    assert_equal "unable", out.first[:decision]
    refute out.first[:ai_refined]
  end

  test "금지 전이(warning→unable)는 무시 → 룰 판정 유지" do
    findings = [ ad_finding(decision: "warning", human_review_required: true) ]
    verdicts = [ verdict(decision: "unable", citation_fact_id: "jp-ad1", confidence: 80) ]
    client = FakeClient.new(response: api_response(verdicts))
    out = LlmScreeningJudge.new(http_client: client).refine(findings, version: @version, country: "JP")
    assert_equal "warning", out.first[:decision]
    refute out.first[:ai_refined]
  end

  test "HTTP 예외 → fail-open(룰 판정 유지)" do
    client = FakeClient.new(error: RuntimeError.new("timeout"))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    assert_equal "unable", out.first[:decision]
  end

  test "non-2xx 응답 → fail-open" do
    client = FakeClient.new(response: FakeResponse.new("500", "internal error"))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    assert_equal "unable", out.first[:decision]
  end

  test "파싱 실패(비JSON) → fail-open" do
    client = FakeClient.new(response: FakeResponse.new("200", "not json{{"))
    out = LlmScreeningJudge.new(http_client: client).refine([ ad_finding ], version: @version, country: "JP")
    assert_equal "unable", out.first[:decision]
  end

  test "응답 사용량(input/output tokens) 메타 노출(last_usage)" do
    client = FakeClient.new(response: api_response([], usage: { "input_tokens" => 111, "output_tokens" => 22 }))
    judge = LlmScreeningJudge.new(http_client: client)
    judge.refine([ ad_finding ], version: @version, country: "JP")
    assert_equal({ input_tokens: 111, output_tokens: 22 }, judge.last_usage)
  end

  private

  def ad_finding(overrides = {})
    { element_type: "ad", decision: "unable", severity: "Major", subject: "안티에이징",
      issue_description: "‘anti-aging’ 표현은 의약외품 경계로 판단이 필요합니다.", recommended_action: nil,
      citation: "JP-AD-CIT", confidence: 58, human_review_required: true }.merge(overrides)
  end

  def verdict(decision:, citation_fact_id:, confidence:, rationale_ko: "근거.", index: 0)
    { "index" => index, "decision" => decision, "rationale_ko" => rationale_ko,
      "citation_fact_id" => citation_fact_id, "confidence" => confidence }
  end

  def api_response(verdicts, code: "200", usage: { "input_tokens" => 100, "output_tokens" => 20 })
    FakeResponse.new(code, {
      "content" => [ { "type" => "tool_use", "name" => "submit_verdicts", "input" => { "verdicts" => verdicts } } ],
      "usage" => usage
    }.to_json)
  end

  def fake_version(*contents)
    Struct.new(:label_texts).new(contents.map { |c| Struct.new(:content).new(c) })
  end
end
