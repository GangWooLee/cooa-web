class Feedback < ApplicationRecord
  belongs_to :component_version
  belongs_to :author, class_name: "User"
  belongs_to :parent, class_name: "Feedback", optional: true
  has_many :replies, class_name: "Feedback", foreign_key: :parent_id, dependent: :destroy

  scope :roots, -> { where(parent_id: nil) }
end
