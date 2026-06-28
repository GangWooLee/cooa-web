# Tenant root (ADR-002 §5.1). The organization's own `id` is the tenant key used by RLS.
class Organization < ApplicationRecord
  REGIONS = %w[JP CN US].freeze
  BILLING_TIERS = %w[starter professional enterprise custom].freeze

  has_many :accounts, foreign_key: :tenant_id, inverse_of: :organization,
                      dependent: :restrict_with_exception
  has_many :role_assignments, foreign_key: :tenant_id, inverse_of: :organization,
                              dependent: :restrict_with_exception

  validates :name, presence: true
  validates :region, inclusion: { in: REGIONS }
  validates :billing_tier, inclusion: { in: BILLING_TIERS }
end
