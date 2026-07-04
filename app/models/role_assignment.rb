# Scoped role grant (ADR-002 §5.2). Replaces the demo's single User.role enum.
# Multiple accounts may hold the same role on one scope (no unique on scope columns+role_key) →
# identity-based SoD (approver_id != submitter_id) is enforced in the approval workflow, not here (Phase 3).
#
# Scope is TYPED (Stage 2 D1): scope_type ∈ {tenant,product,component} with a matching typed FK column
# (both NULL for tenant, scope_product_id for product, scope_component_id for component). The DB CHECK
# ra_scope_coherence is the hard backstop; scope_columns_match_type mirrors it at the model.
class RoleAssignment < ApplicationRecord
  ROLE_KEYS = %w[owner brand_admin ra_reviewer approver assignee contributor viewer external_collaborator].freeze
  SCOPE_TYPES = %w[tenant product component].freeze
  MARKETS = %w[JP CN US].freeze

  belongs_to :account
  belongs_to :organization, foreign_key: :tenant_id, inverse_of: :role_assignments

  validates :role_key, inclusion: { in: ROLE_KEYS }
  validates :scope_type, inclusion: { in: SCOPE_TYPES }
  validates :market, inclusion: { in: MARKETS }, allow_nil: true
  validate :scope_columns_match_type
  validate :owner_must_be_tenant_wide

  before_destroy :guard_last_owner          # P6 #3: removing the last owner grant is refused
  before_update :guard_last_owner_on_expire # …as is expiring it

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) } # SQL expiry (P4) — SQL twin of active?
  # Tenant-wide = no typed scope set (the grant applies across the whole tenant). Replaces `scope_id: nil`.
  scope :tenant_wide, -> { where(scope_product_id: nil, scope_component_id: nil) }

  def active? = expires_at.nil? || expires_at.future?
  def tenant_wide? = scope_product_id.nil? && scope_component_id.nil?

  private

  # Mirror of the DB CHECK ra_scope_coherence — surfaces the mismatch as a validation error (not a raw
  # PG::CheckViolation) and covers app-built grants before they hit the DB.
  def scope_columns_match_type
    case scope_type
    when "tenant"
      if scope_product_id.present? || scope_component_id.present?
        errors.add(:scope_type, "tenant grant must not set a product/component scope")
      end
    when "product"
      errors.add(:scope_product_id, "is required for a product-scoped grant") if scope_product_id.blank?
      errors.add(:scope_component_id, "must be blank for a product-scoped grant") if scope_component_id.present?
    when "component"
      errors.add(:scope_component_id, "is required for a component-scoped grant") if scope_component_id.blank?
      errors.add(:scope_product_id, "must be blank for a component-scoped grant") if scope_product_id.present?
    end
  end

  # owner is a TENANT role by construction — LastOwnerGuard and EligibleApproverService both assume
  # "owner ⇒ tenant-wide". Promote that assumption to a rule so a scoped owner grant can never exist.
  def owner_must_be_tenant_wide
    errors.add(:role_key, "owner grants must be tenant-wide") if role_key == "owner" && !tenant_wide?
  end

  def guard_last_owner
    return unless owner_grant? && active? && account&.active?
    LastOwnerGuard.ensure_owner_remains!(tenant_id, account_id)
  end

  def guard_last_owner_on_expire
    return unless owner_grant? && account&.active?
    return unless expires_at_changed? && (expires_at_was.nil? || expires_at_was > Time.current) && !active?
    LastOwnerGuard.ensure_owner_remains!(tenant_id, account_id)
  end

  def owner_grant? = role_key == "owner" && tenant_wide?
end
