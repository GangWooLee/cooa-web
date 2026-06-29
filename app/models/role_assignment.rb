# Scoped role grant (ADR-002 §5.2). Replaces the demo's single User.role enum.
# Multiple accounts may hold the same role on one scope (no unique on scope_id+role_key) →
# identity-based SoD (approver_id != submitter_id) is enforced in the approval workflow, not here (Phase 3).
class RoleAssignment < ApplicationRecord
  ROLE_KEYS = %w[owner brand_admin ra_reviewer approver assignee contributor viewer external_collaborator].freeze
  SCOPE_TYPES = %w[tenant product component].freeze
  MARKETS = %w[JP CN US].freeze

  belongs_to :account
  belongs_to :organization, foreign_key: :tenant_id, inverse_of: :role_assignments

  validates :role_key, inclusion: { in: ROLE_KEYS }
  validates :scope_type, inclusion: { in: SCOPE_TYPES }
  validates :market, inclusion: { in: MARKETS }, allow_nil: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) } # SQL expiry (P4) — SQL twin of active?
  def active? = expires_at.nil? || expires_at.future?
end
