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

  before_destroy :guard_last_owner          # P6 #3: removing the last owner grant is refused
  before_update :guard_last_owner_on_expire # …as is expiring it

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) } # SQL expiry (P4) — SQL twin of active?
  def active? = expires_at.nil? || expires_at.future?

  private

  def guard_last_owner
    return unless owner_grant? && active? && account&.active?
    LastOwnerGuard.ensure_owner_remains!(tenant_id, account_id)
  end

  def guard_last_owner_on_expire
    return unless owner_grant? && account&.active?
    return unless expires_at_changed? && (expires_at_was.nil? || expires_at_was > Time.current) && !active?
    LastOwnerGuard.ensure_owner_remains!(tenant_id, account_id)
  end

  def owner_grant? = role_key == "owner" && scope_id.nil?
end
