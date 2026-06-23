class IngredientLimit < ApplicationRecord
  scope :for_country, ->(c) { where(country: c) }

  def banned? = restriction_type == "banned"
  def capped? = max_pct.present? && %w[max_concentration max_pct restricted conditional].include?(restriction_type)
end
