class ComponentVersion < ApplicationRecord
  belongs_to :component
  belongs_to :created_by, class_name: "User", optional: true

  has_many :ingredients, -> { order(:position, :id) }, dependent: :destroy
  has_many :label_texts, dependent: :destroy
  has_many :feedbacks, -> { order(:created_at) }, dependent: :destroy
  has_many :check_items, -> { order(:position, :id) }, dependent: :destroy
  has_many :screening_runs, dependent: :destroy
  has_many :diffs_from_here, class_name: "VersionDiff", foreign_key: :from_version_id, dependent: :destroy

  def vlabel = "v#{version_number}"
  def product = component.product
  def latest_screening = screening_runs.order(:created_at).last
end
