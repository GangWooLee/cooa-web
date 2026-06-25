# 4-enum 판정의 표시 메타(라벨·색·아이콘) 공유 — ScreeningRun/ScreeningFinding 공용
module Decidable
  extend ActiveSupport::Concern

  DECISIONS = {
    "ok"        => { label: "적합",     color: "#84b733", bg: "#eef6e3", icon: "check" },
    "warning"   => { label: "주의",     color: "#e6a700", bg: "#fff7e0", icon: "warn" },
    "violation" => { label: "위반",     color: "#8e0300", bg: "#fdeceb", icon: "x" },
    "unable"    => { label: "판단불가", color: "#6b7280", bg: "#f1f1f1", icon: "question" }
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
