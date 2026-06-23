class ComponentVersion < ApplicationRecord
  belongs_to :component
  belongs_to :created_by, class_name: "User", optional: true

  has_many :ingredients, -> { order(:position, :id) }, dependent: :destroy
  has_many :label_texts, dependent: :destroy
  has_many :annotations, -> { order(:seq, :position) }, dependent: :destroy
  has_many :screening_runs, dependent: :destroy

  def vlabel = "v#{version_number}"
  def product = component.product
  def latest_screening = screening_runs.order(:created_at).last
end
