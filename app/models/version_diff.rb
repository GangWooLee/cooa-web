class VersionDiff < ApplicationRecord
  belongs_to :from_version, class_name: "ComponentVersion"
  belongs_to :to_version, class_name: "ComponentVersion"

  scope :ordered, -> { order(:marker_label, :position, :id) }
end
