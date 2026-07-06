# 어노테이션 = 아트워크 위 바운딩박스 피드백 (위치 + 카테고리 + 코멘트 스레드 + 해소상태)
class Annotation < ApplicationRecord
  include TenantScoped
  belongs_to :component_version
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :resolved_in_version, class_name: "ComponentVersion", optional: true
  belongs_to :resolved_by, class_name: "User", optional: true
  has_many :comments, -> { order(:created_at, :id) }, class_name: "AnnotationComment", dependent: :destroy

  enum :status, { open: "open", resolved: "resolved", dismissed: "dismissed" }, default: "open"

  CATEGORY_COLORS = {
    "오탈자" => "#e6a700", "인허가" => "#8e0300", "디자인" => "#4f74e3", "기타" => "#6b7280"
  }.freeze
  # 상태 알약(3중 신호: 색+라벨+아이콘). 라벨은 액션 동사(반영됨으로 표시·반영 확인)와 정합하는 반영/미반영으로 통일.
  STATUS_META = {
    "open"      => { label: "미반영", color: "#8e0300", bg: "#fdeceb", icon: "clock" },
    "resolved"  => { label: "반영",   color: "#5f8f2e", bg: "#eef6e3", icon: "check" },
    "dismissed" => { label: "보류",   color: "#6b7280", bg: "#f1f1f1", icon: "x" }
  }.freeze

  scope :ordered, -> { order(:seq, :position, :id) }

  def status_meta = STATUS_META[status] || STATUS_META["open"]
  def box_color   = resolved? ? "#5f8f2e" : (CATEGORY_COLORS[category] || "#8e0300")
  def author_name = created_by&.name
end
