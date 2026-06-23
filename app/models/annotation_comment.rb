# 어노테이션 코멘트 스레드 (담당자 피드백 + 답글)
class AnnotationComment < ApplicationRecord
  belongs_to :annotation
  belongs_to :author, class_name: "User"
  belongs_to :parent, class_name: "AnnotationComment", optional: true
  has_many :replies, class_name: "AnnotationComment", foreign_key: :parent_id, dependent: :destroy

  scope :roots, -> { where(parent_id: nil) }
end
