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
    "오탈자" => "var(--color-warn)", "인허가" => "var(--color-cooa)",
    "디자인" => "var(--color-ink)", "기타" => "var(--color-muted)"
  }.freeze
  # 상태 알약(3중 신호: 색+라벨+아이콘). 라벨은 액션 동사(반영됨으로 표시·반영 확인)와 정합하는 반영/미반영으로 통일.
  STATUS_META = {
    "open"      => { label: "미반영", color: "var(--color-cooa)", bg: "var(--color-accent)", icon: "clock", text: "var(--color-cooa)" },
    "resolved"  => { label: "반영",   color: "var(--color-ok-strong)", bg: "var(--color-ok-soft)", icon: "check", text: "var(--color-ink)" },
    "dismissed" => { label: "보류",   color: "var(--color-muted)", bg: "var(--color-tint)", icon: "x", text: "var(--color-ink)" }
  }.freeze

  scope :ordered, -> { order(:seq, :position, :id) }

  def status_meta = STATUS_META[status] || STATUS_META["open"]
  def box_color   = resolved? ? "var(--color-ok-strong)" : (CATEGORY_COLORS[category] || "var(--color-cooa)")
  def author_name = created_by&.name
end
