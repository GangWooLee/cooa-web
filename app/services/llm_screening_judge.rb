require "net/http"
require "json"

# JP 한정 LLM 하이브리드 보조판정 — 룰 선행, LLM은 '경계 사례'(판단불가·RA검토 주의)만 재판정한다.
#  · 정직: LLM 판정이라도 human_review_required는 항상 유지(RA 최종 확인 필요).
#  · 인용 바인딩(resolve-then-judge): LLM이 인용한 fact_id가 제공 집합 밖이면 그 판정을 폐기(환각 인용 기각).
#  · 키 없으면 완전 무변경(available? == false → findings 그대로) — 룰-only 경로는 기존 CI와 무풍.
#  · 실패(HTTP/타임아웃/파싱)는 fail-open to rule: 룰 판정을 그대로 두고 warn 1줄만 남긴다.
# 룰 선행 계약상 violation(하드 판정) finding은 경계 대상이 아니므로 절대 뒤집히지 않는다.
class LlmScreeningJudge
  API_URL = "https://api.anthropic.com/v1/messages".freeze
  ANTHROPIC_VERSION = "2023-06-01".freeze
  DEFAULT_MODEL = "claude-haiku-4-5-20251001".freeze
  MAX_TOKENS = 2048
  TIMEOUT_S = 10
  LABEL_CONTEXT_CAP = 2000
  MAX_FACTS_PER_AXIS = 25
  CONFIDENCE_MIN = 55
  CONFIDENCE_MAX = 95

  # 허용 decision 전이(guard ③). "그 외 조합"(동일 판정 포함)은 무시 → 룰 판정 유지.
  # violation은 source 키가 없다 = 룰 하드 판정 불변(guard ②).
  ALLOWED_TRANSITIONS = {
    "unable"  => %w[ok warning violation],
    "warning" => %w[ok violation]
  }.freeze

  SUBMIT_VERDICTS_TOOL = {
    name: "submit_verdicts",
    description: "각 경계 finding에 대한 재판정 결과를 제출한다. 제공된 fact만 인용 가능.",
    input_schema: {
      type: "object",
      properties: {
        verdicts: {
          type: "array",
          items: {
            type: "object",
            properties: {
              index: { type: "integer", description: "경계 finding 목록의 0-기반 인덱스" },
              decision: { type: "string", enum: %w[ok warning violation unable] },
              rationale_ko: { type: "string", description: "한국어 근거 1-2문장" },
              citation_fact_id: { type: "string", description: "인용한 규제 fact의 fact_id (제공 목록 안에서만)" },
              confidence: { type: "integer", description: "0-100 신뢰도" }
            },
            required: %w[index decision rationale_ko citation_fact_id confidence]
          }
        }
      },
      required: %w[verdicts]
    }
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    당신은 일본(JP) 화장품 표시·광고 규제의 보조 심사원이다. 룰엔진이 '경계 사례'로 넘긴 finding만 재판정한다.
    규칙:
    - 제공된 규제 fact 목록 안의 fact_id만 인용할 수 있다. 목록에 없는 근거는 절대 만들어내지 마라.
    - 근거가 불충분하면 기존 판정(대개 unable)을 유지하라. 확신이 있을 때만 판정을 바꿔라.
    - rationale_ko는 한국어 1-2문장으로, 어떤 fact에 근거해 그렇게 판단했는지 밝혀라.
    - 최종 결재는 사람(RA)이 한다. 너의 판정은 보조 의견이다.
    반드시 submit_verdicts 도구로만 응답하라.
  PROMPT

  attr_reader :last_usage

  def self.refine(findings, version:, country:, http_client: nil)
    new(http_client: http_client).refine(findings, version: version, country: country)
  end

  def initialize(http_client: nil)
    @http_client = http_client
    @last_usage = nil
  end

  def available? = api_key.present?

  # 경계 사례만 재판정하고 (부분) 갱신된 findings 배열을 반환. AI가 바꾼 finding엔 transient :ai_refined 마킹
  #  → ScreeningService가 집계(summary 표기)에 쓰고 영속 전 제거한다(스키마 컬럼 아님).
  def refine(findings, version:, country:)
    return findings unless country == "JP" && available?
    # 테스트에서는 주입된 fake 클라이언트가 있을 때만 동작 — 개발자 셸에 실키가 있어도
    # 스위트가 실 API를 치지 않게(비결정성·과금·JP 스크리닝 테스트 전반 오염 방지).
    return findings if Rails.env.test? && @http_client.nil?

    boundary = findings.select { |f| boundary_case?(f) }
    return findings if boundary.empty?

    facts = collect_facts(boundary, country)
    verdicts = request_verdicts(boundary, facts, version) # 실패 시 raise → 아래 rescue
    apply_verdicts(findings, boundary, verdicts, facts)
  rescue StandardError => e
    Rails.logger.warn("[LlmScreeningJudge] fail-open to rule verdicts — #{e.class}: #{e.message}")
    findings
  end

  private

  def boundary_case?(finding)
    finding[:decision] == "unable" ||
      (finding[:decision] == "warning" && finding[:human_review_required])
  end

  # 경계 finding의 축(element_type)별 JP KB 행을 fact_id·요지·citation으로 카탈로그화.
  # 축당 상한: 유발 fact(citation 일치) → subject 매칭 → 나머지 순으로 정렬 후 상한까지(프롬프트 폭주 방지).
  def collect_facts(boundary, country)
    catalog = {}
    boundary.group_by { |f| f[:element_type] }.each do |axis, axis_findings|
      trigger_citations = axis_findings.filter_map { |f| f[:citation] }
      subjects = axis_findings.filter_map { |f| f[:subject].to_s.downcase.presence }
      prioritized = kb_rows(axis, country).to_a.sort_by do |row|
        [ fact_priority(axis, row, trigger_citations, subjects), row.id ]
      end
      prioritized.first(MAX_FACTS_PER_AXIS).each do |row|
        fid = fact_id_for(axis, row)
        catalog[fid] ||= { fact_id: fid, axis: axis, summary: fact_summary(axis, row), citation: row.citation.to_s }
      end
    end
    catalog
  end

  def fact_priority(axis, row, trigger_citations, subjects)
    subj = row_subject(axis, row).to_s.downcase
    return 0 if row.citation.present? && trigger_citations.include?(row.citation)
    return 1 if subj.present? && subjects.any? { |s| subj.include?(s) || s.include?(subj) }
    2
  end

  def kb_rows(axis, country)
    case axis
    when "ingredient" then IngredientLimit.for_country(country)
    when "ad"         then AdRiskExpression.for_country(country)
    when "label"      then LabelRequirement.for_country(country)
    else []
    end
  end

  def row_subject(axis, row)
    case axis
    when "ingredient" then row.inci_canonical
    when "ad"         then [ row.keyword_ko, row.keyword_native ].compact.join(" ")
    when "label"      then row.item
    end
  end

  def fact_summary(axis, row)
    case axis
    when "ingredient"
      cap = row.max_pct.present? ? " · 상한 #{row.max_pct}%" : ""
      "성분 #{row.inci_canonical}: #{row.restriction_type}#{cap} (#{row.category})"
    when "ad"
      "광고표현 '#{row.keyword_ko}'(#{row.keyword_native}) 위험도 #{row.risk_level}"
    when "label"
      "필수 표시 항목 '#{row.item}'"
    end
  end

  # fact_id: KB 행의 fact_id 우선, 없으면 축+id로 합성(항상 존재·바인딩 키로 안정적).
  def fact_id_for(axis, row) = row.fact_id.presence || "#{axis[0, 3]}-#{row.id}"

  def request_verdicts(boundary, facts, version)
    json = build_body(boundary, facts, version).to_json
    response = post(json)
    raise "HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

    payload = JSON.parse(response.body)
    usage = payload["usage"] || {}
    @last_usage = { input_tokens: usage["input_tokens"], output_tokens: usage["output_tokens"] }
    Rails.logger.info(
      "[LlmScreeningJudge] model=#{model} boundary=#{boundary.size} " \
      "in=#{usage['input_tokens']} out=#{usage['output_tokens']}"
    )
    extract_verdicts(payload)
  end

  def build_body(boundary, facts, version)
    {
      model: model,
      max_tokens: MAX_TOKENS,
      system: SYSTEM_PROMPT,
      tools: [ SUBMIT_VERDICTS_TOOL ],
      tool_choice: { type: "tool", name: "submit_verdicts" },
      messages: [ { role: "user", content: build_user_prompt(boundary, facts, version) } ]
    }
  end

  def build_user_prompt(boundary, facts, version)
    findings_lines = boundary.each_with_index.map do |f, i|
      "#{i}. [#{f[:element_type]}] 주제=\"#{f[:subject]}\" 현재판정=#{f[:decision]} — #{f[:issue_description]}"
    end
    fact_lines = facts.values.map do |fact|
      "- fact_id=#{fact[:fact_id]} [#{fact[:axis]}] #{fact[:summary]} · 출처: #{fact[:citation]}"
    end
    label_context = version.label_texts.map { |t| t.content.to_s }.join("\n").slice(0, LABEL_CONTEXT_CAP)

    <<~USER
      [경계 finding — 각 index를 재판정하라]
      #{findings_lines.join("\n")}

      [제공 규제 fact — 이 목록의 fact_id만 인용 가능]
      #{fact_lines.join("\n")}

      [라벨 원문 컨텍스트]
      #{label_context}

      각 finding index에 대해 submit_verdicts로 결과를 제출하라. 확신이 없으면 unable을 유지하고,
      citation_fact_id는 위 fact 목록 안에서만 선택하라.
    USER
  end

  def extract_verdicts(payload)
    block = Array(payload["content"]).find { |b| b["type"] == "tool_use" && b["name"] == "submit_verdicts" }
    raise "no submit_verdicts tool_use in response" if block.nil?
    Array(block.dig("input", "verdicts"))
  end

  # index → verdict 매핑 후 경계 finding만 갱신. 나머지는 원본 그대로.
  def apply_verdicts(all_findings, boundary, verdicts, facts)
    by_index = verdicts.each_with_object({}) do |v, h|
      idx = v["index"]
      h[idx] = v if idx.is_a?(Integer) && idx.between?(0, boundary.size - 1)
    end

    all_findings.map do |finding|
      b_idx = boundary.index { |b| b.equal?(finding) }
      verdict = b_idx && by_index[b_idx]
      verdict ? (refined_finding(finding, verdict, facts) || finding) : finding
    end
  end

  def refined_finding(finding, verdict, facts)
    fact = facts[verdict["citation_fact_id"]]
    return nil if fact.nil? # guard ①: 인용 fact 집합 밖 → 폐기(룰 판정 유지)

    allowed = ALLOWED_TRANSITIONS[finding[:decision]] || []
    return nil unless allowed.include?(verdict["decision"]) # guard ③

    rationale = verdict["rationale_ko"].to_s.strip
    return nil if rationale.blank?

    finding.merge(
      decision: verdict["decision"],
      issue_description: "#{finding[:issue_description]}\nAI 보조판정: #{rationale}", # guard ⑥
      citation: fact[:citation].presence || finding[:citation],                       # 바인딩된 fact citation
      confidence: clamp_confidence(verdict["confidence"]),
      human_review_required: true,                                                    # guard ④: 항상 유지
      ai_refined: true                                                                # transient 마커(영속 전 제거)
    )
  end

  def clamp_confidence(raw) = raw.to_i.clamp(CONFIDENCE_MIN, CONFIDENCE_MAX)

  def post(json_body)
    return @http_client.post(url: API_URL, headers: request_headers, body: json_body) if @http_client

    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT_S
    http.read_timeout = TIMEOUT_S
    request = Net::HTTP::Post.new(uri)
    request_headers.each { |k, v| request[k] = v }
    request.body = json_body
    http.request(request)
  end

  def request_headers
    { "content-type" => "application/json", "x-api-key" => api_key, "anthropic-version" => ANTHROPIC_VERSION }
  end

  def api_key = ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)

  def model = ENV.fetch("LLM_JUDGE_MODEL", DEFAULT_MODEL)
end
