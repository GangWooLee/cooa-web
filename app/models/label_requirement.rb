class LabelRequirement < ApplicationRecord
  scope :for_country, ->(c) { where(country: c) }
end
