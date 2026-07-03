class ScreeningFinding < ApplicationRecord
  include TenantScoped
  include Decidable

  belongs_to :screening_run
  enum :decision, { ok: "ok", warning: "warning", violation: "violation", unable: "unable" }, prefix: :decision
  enum :element_type,
       { ingredient: "ingredient", label: "label", ad: "ad", design: "design" },
       default: "ingredient", prefix: :element

  ELEMENT_LABELS = { "ingredient" => "성분", "label" => "라벨", "ad" => "광고/표현", "design" => "디자인" }.freeze
  def element_label = ELEMENT_LABELS[element_type]

  # 아트워크 위 finding 위치(바운딩박스)
  def boxed? = [ box_x, box_y, box_w, box_h ].all?(&:present?)
end
