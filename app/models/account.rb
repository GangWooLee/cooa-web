# Login identity, single-tenant (ADR-002 §5.1). The authenticated principal in Phase 2.
# Email is unique PER TENANT (see migration) — never global.
class Account < ApplicationRecord
  STATUSES = %w[invited active suspended deprovisioned].freeze

  belongs_to :organization, foreign_key: :tenant_id, inverse_of: :accounts
  # Strategy B (Phase 2a-1): the linked User is the domain "person" (owner_id / *_by_id FK target) and
  # the display source. Optional so Phase 2b Keycloak JIT can create accounts before/without a User.
  belongs_to :user, optional: true
  has_many :role_assignments, dependent: :destroy

  before_update :guard_last_owner_on_deactivate # P6 #3: refuse suspend/deprovision of the last active owner
  before_destroy :guard_last_owner_on_destroy

  validates :email, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  # Display delegation — views/helpers keep calling .name/.avatar_color/.role_* on the principal.
  delegate :name, :initial, :role_label, :role_short, :avatar_color, to: :user, allow_nil: true

  def active? = status == "active"

  # SoD identity bridge: actor_id must live in the domain FK space (User bigint), not the Account uuid,
  # or `requested_by_id != actor_id` is always true (self-approval fail-open). See AccessContext#actor_id.
  def domain_user_id = user_id

  # Revoke-all: every bump invalidates outstanding sessions/tokens (ADR-003 §3.3). Checked per-request.
  def bump_token_version! = increment!(:token_version)

  private

  # Suspend/deprovision an account that is CURRENTLY an active owner → must leave another active owner.
  def guard_last_owner_on_deactivate
    return unless status_changed? && status_was == "active" && !active?
    LastOwnerGuard.ensure_owner_remains!(tenant_id, id) if owner_grant?
  end

  # Destroy cascades role_assignments (dependent: :destroy) — the RoleAssignment guard also fires — but
  # guard here too so the refusal is explicit regardless of callback ordering.
  def guard_last_owner_on_destroy
    LastOwnerGuard.ensure_owner_remains!(tenant_id, id) if active? && owner_grant?
  end

  def owner_grant?
    role_assignments.active.exists?(role_key: "owner", scope_id: nil)
  end
end
