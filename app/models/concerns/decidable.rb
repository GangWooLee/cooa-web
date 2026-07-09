# 4-enum 판정의 표시 메타(라벨·색·아이콘) 공유 — ScreeningRun/ScreeningFinding 공용
module Decidable
  extend ActiveSupport::Concern

  DECISIONS = {
    "ok"        => { label: "적합",     color: "var(--color-ok-strong)", bg: "var(--color-ok-soft)", icon: "check", text: "var(--color-ink)" },
    "warning"   => { label: "주의",     color: "var(--color-warn)", bg: "var(--color-warn-soft)", icon: "warn", text: "var(--color-ink)" },
    "violation" => { label: "위반",     color: "var(--color-cooa)", bg: "var(--color-accent)", icon: "x", text: "var(--color-cooa)" },
    "unable"    => { label: "판단불가", color: "var(--color-muted)", bg: "var(--color-tint)", icon: "question", text: "var(--color-ink)" }
  }.freeze

  # 여러 판정 중 최악(가장 심각) 하나를 고른다 — 종합 판정 계산용.
  # 순서: 적합 < 판단불가 < 주의 < 위반. (실재 우려인 '주의'가 미결정 '판단불가'에 가려지지 않게 —
  #  build_summary 표시순 "위반·위험(주의)·판단불가"와도 정합.)
  SEVERITY_ORDER = %w[ok unable warning violation].freeze

  def decision_meta = DECISIONS[decision] || DECISIONS["unable"]
  def decision_label = decision_meta[:label]

  class_methods do
    def worst_decision(decisions)
      decisions.compact.max_by { |d| SEVERITY_ORDER.index(d) || 0 } || "ok"
    end
  end
end
