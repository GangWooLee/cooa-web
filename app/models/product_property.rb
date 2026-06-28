class ProductProperty < ApplicationRecord
  include TenantScoped
  belongs_to :product
  normalizes :name, with: ->(v) { v.to_s.strip }
  validates :name, presence: true
  scope :ordered, -> { order(:position, :id) }
end
