class AdRiskExpression < ApplicationRecord
  scope :for_country, ->(c) { where(country: c) }
end
