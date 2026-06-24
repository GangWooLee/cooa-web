# 인허가 스크리닝 룰엔진 (결정론적 · 재현가능 · 인용 우선)
#  COOA의 "Rule-First" 1차 필터를 LLM 없이 충실히 구현:
#   ① 성분 → IngredientLimit 대조 (banned/over-limit; 데이터 신뢰도로 판정 조절)
#   ② 광고/표현 → AdRiskExpression 키워드 매칭 (국가별 의약외품/금지 경계)
#   ③ 라벨 필수항목 → LabelRequirement match_keyword 충족 여부
class ScreeningService
  Result = Struct.new(:decision, :findings, :summary)

  def initialize(version, country)
    @version = version
    @country = country
  end

  # 판정만 계산 (미저장)
  def call
    findings = ingredient_findings + ad_findings + label_findings
    assign_boxes(findings)
    decision = ScreeningFinding.worst_decision(findings.map { |f| f[:decision] })
    Result.new(decision, findings, build_summary(findings, decision))
  end

  # ScreeningRun + ScreeningFinding 영속화
  def run!(requested_by:)
    result = call
    run = @version.screening_runs.create!(
      country: @country, requested_by: requested_by, status: "completed",
      decision: result.decision, summary: result.summary
    )
    result.findings.each_with_index { |f, i| run.screening_findings.create!(f.merge(position: i)) }
    run
  end

  private

  # ① 성분
  def ingredient_findings
    @version.ingredients.map do |ing|
      limit = IngredientLimit.for_country(@country).find_by(inci_canonical: ing.inci_canonical)
      next ok_finding(ing, nil) if limit.nil?

      if limit.banned?
        finding(element_type: "ingredient", decision: "violation", severity: "Critical", subject: ing.inci_name,
                issue_description: "#{cl} 사용 금지 성분입니다.", recommended_action: "해당 성분을 제거하거나 대체 성분으로 교체하세요.",
                citation: limit.citation, confidence: 96)
      elsif limit.capped? && over_limit?(ing, limit) # 농도 상한 규제일 때만(restriction_type 반영, false-positive 차단)
        if limit.status == "structured"
          finding(element_type: "ingredient", decision: "violation", severity: "Major", subject: ing.inci_name,
                  issue_description: "라벨 선언 농도 #{pct(ing.declared_pct)} > #{cl} 한도 #{pct(limit.max_pct)} (#{limit.category}).",
                  recommended_action: "농도를 #{pct(limit.max_pct)} 이하로 조정하거나 의약외품 경로를 검토하세요.",
                  citation: limit.citation, confidence: 92)
        else
          finding(element_type: "ingredient", decision: "warning", severity: "Major", subject: ing.inci_name,
                  issue_description: "선언 농도 #{pct(ing.declared_pct)}가 #{cl} 한도 #{pct(limit.max_pct)}를 초과할 수 있습니다(데이터 미검증).",
                  recommended_action: "1차 법령으로 한도를 확인 후 조정하세요.",
                  citation: limit.citation, confidence: 68, human_review_required: true)
        end
      else
        ok_finding(ing, limit.citation)
      end
    end
  end

  # ② 광고/표현
  def ad_findings
    blob = label_blob
    AdRiskExpression.for_country(@country).filter_map do |ex|
      hit = keywords(ex.keyword_native).find { |k| blob.include?(k) }
      next unless hit

      if @country == "JP" && ex.risk_level == "critical"
        finding(element_type: "ad", decision: "unable", severity: "Major", subject: ex.keyword_ko,
                issue_description: "‘#{hit}’ 표현은 일본에서 의약외품(医薬部外品) 경계로 분류 판단이 필요합니다.",
                recommended_action: "PMDA 의약외품 심사 필요 여부를 RA가 확인해야 합니다.",
                citation: ex.citation, confidence: 58, human_review_required: true)
      elsif @country == "CN" && ex.risk_level == "critical"
        finding(element_type: "ad", decision: "violation", severity: "Critical", subject: ex.keyword_ko,
                issue_description: "‘#{hit}’ 의료작용 표현은 중국에서 금지됩니다(Order 727 §37).",
                recommended_action: "의료적 표현을 삭제하세요.", citation: ex.citation, confidence: 90)
      else
        finding(element_type: "ad", decision: "warning", severity: "Minor", subject: ex.keyword_ko,
                issue_description: "‘#{hit}’ 표현은 표시·광고 위험(#{ex.risk_level})이 있습니다.",
                recommended_action: "완곡 표현으로 수정하거나 근거 자료를 확보하세요.", citation: ex.citation, confidence: 72)
      end
    end
  end

  # ③ 라벨 필수항목 (match_keyword 있는 것만 자동 판정)
  def label_findings
    blob = label_blob
    LabelRequirement.for_country(@country).where.not(match_keyword: [ nil, "" ]).filter_map do |req|
      present = keywords(req.match_keyword).any? { |k| blob.include?(k) }
      next if present

      finding(element_type: "label", decision: "warning", severity: "Major", subject: req.item,
              issue_description: "필수 표시 항목 ‘#{req.item}’이(가) 라벨에서 확인되지 않습니다.",
              recommended_action: "해당 항목을 라벨에 추가하세요.", citation: req.citation, confidence: 80, human_review_required: true)
    end
  end

  # ── helpers ──
  # finding 위치(아트워크 위 바운딩박스, 데모 큐레이션 — 실제 CV 아님)
  def assign_boxes(findings)
    findings.each do |f|
      next if f[:decision] == "ok"
      box =
        case f[:element_type]
        when "ingredient" then ([ 48.0, 34.0, 12.0, 4.5 ] if f[:subject].to_s.upcase == "RETINOL")
        when "ad"         then [ 22.0, 46.5, 16.0, 4.5 ]   # 전면 패널 Anti-Aging Formula
        when "label"
          s = f[:subject].to_s
          if s.include?("재활용") then [ 69.5, 70.5, 9.0, 6.0 ]
          elsif s.include?("製造販売業者") || s.include?("DMAH") then [ 62.5, 63.5, 17.0, 6.0 ]
          end
        end
      f[:box_x], f[:box_y], f[:box_w], f[:box_h] = box if box
    end
  end

  def over_limit?(ing, limit)
    limit.max_pct.present? && ing.declared_pct.present? && ing.declared_pct > limit.max_pct
  end

  def ok_finding(ing, citation)
    finding(element_type: "ingredient", decision: "ok", severity: "Minor", subject: ing.inci_name,
            issue_description: "#{cl} 규정상 허용 범위입니다.", citation: citation, confidence: 88)
  end

  # 키워드 인자 — 콜사이트 자기문서화·인자 전치 방지(이전 9-위치인자 리팩터)
  def finding(element_type:, decision:, severity:, subject:, issue_description:, confidence:,
              recommended_action: nil, citation: nil, human_review_required: false)
    { element_type: element_type, decision: decision, severity: severity, subject: subject,
      issue_description: issue_description, recommended_action: recommended_action, citation: citation,
      confidence: confidence, human_review_required: human_review_required }
  end

  def label_blob = @label_blob ||= @version.label_texts.map { |t| t.content.to_s.downcase }.join("  ")
  def keywords(str) = str.to_s.downcase.split("|").map(&:strip).reject(&:blank?)
  def cl = "#{ApplicationRecord.country_label(@country)}에서"
  def pct(v) = "#{v.to_f.round(2).to_s.sub(/\.0+$/, '')}%"

  def build_summary(findings, decision)
    c = findings.group_by { |f| f[:decision] }.transform_values(&:size)
    label = (Decidable::DECISIONS[decision] || Decidable::DECISIONS["unable"])[:label]
    "#{ApplicationRecord.country_label(@country)} 기준 종합 #{label} · " \
      "위반 #{c['violation'].to_i} · 위험 #{c['warning'].to_i} · 판단불가 #{c['unable'].to_i} · 적합 #{c['ok'].to_i}"
  end
end
