# 어노테이션 = 아트워크 위 바운딩박스 피드백 (위치 + 카테고리 + 코멘트 스레드 + 해소상태)
class Annotation < ApplicationRecord
  belongs_to :component_version
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :resolved_in_version, class_name: "ComponentVersion", optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
  has_many :comments, -> { order(:created_at) }, class_name: "AnnotationComment", dependent: :destroy

  enum :status, { open: "open", resolved: "resolved", dismissed: "dismissed" }, default: "open"

  CATEGORY_COLORS = {
    "오탈자" => "#e6a700", "인허가" => "#8e0300", "디자인" => "#4f74e3", "기타" => "#6b7280"
  }.freeze
  STATUS_META = {
    "open"      => { label: "미해결", color: "#8e0300", bg: "#fdeceb" },
    "resolved"  => { label: "해결",   color: "#5f8f2e", bg: "#eef6e3" },
    "dismissed" => { label: "보류",   color: "#6b7280", bg: "#f1f1f1" }
  }.freeze

  scope :ordered, -> { order(:seq, :position, :id) }

  def status_meta = STATUS_META[status] || STATUS_META["open"]
  def box_color   = resolved? ? "#5f8f2e" : (CATEGORY_COLORS[category] || "#8e0300")
  def author_name = created_by&.name
end
