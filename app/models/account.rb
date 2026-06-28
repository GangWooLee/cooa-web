# Login identity, single-tenant (ADR-002 §5.1). Will replace the demo `User` in Phase 2.
# Email is unique PER TENANT (see migration) — never global.
class Account < ApplicationRecord
  STATUSES = %w[invited active suspended deprovisioned].freeze

  belongs_to :organization, foreign_key: :tenant_id, inverse_of: :accounts
  has_many :role_assignments, dependent: :destroy

  validates :email, presence: true
  validates :status, inclusion: { in: STATUSES }

  def active? = status == "active"

  # Revoke-all: every bump invalidates outstanding sessions/tokens (ADR-003 §3.3). Wired in Phase 2.
  def bump_token_version! = increment!(:token_version)
end
