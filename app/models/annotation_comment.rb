# 어노테이션 코멘트 스레드 (담당자 피드백 + 답글)
class AnnotationComment < ApplicationRecord
  include TenantScoped
  belongs_to :annotation
  belongs_to :author, class_name: "User"
  belongs_to :parent, class_name: "AnnotationComment", optional: true
  has_many :replies, class_name: "AnnotationComment", foreign_key: :parent_id, dependent: :destroy

  # 입력 위생(S1): 과도한 피드백 본문 거부(nil/빈값 허용). 메시지 한글(full_messages 영문 회피).
  validates :body, length: { maximum: 2000, message: "— 2000자를 넘을 수 없습니다" }

  scope :roots, -> { where(parent_id: nil) }
end
