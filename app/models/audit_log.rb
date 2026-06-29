# Append-only, hash-chained audit log (ADR-002 §5.4). Immutable at the DB (RLS + SELECT/INSERT-only
# grant + BEFORE UPDATE/DELETE trigger); chained per-tenant (prev_chain_hash → chain_hash) so any
# tamper or gap is detectable by `rails audit:verify`. Records BOTH allow and deny.
class AuditLog < ApplicationRecord
  ADVISORY_NS = 0x4155 # "AU" — namespace for the per-tenant chain advisory lock

  belongs_to :organization, foreign_key: :tenant_id, optional: true

  validates :outcome, inclusion: { in: %w[allow deny] } # m-4 (P2): reject non-canonical outcomes

  before_create :assign_chain

  # The single write API. tenant/actor/region come from Current; request_id/source_ip/user_agent from
  # the caller (controller). allow REQUIRES a domain actor (fail-CLOSED — a User-less Account must not
  # silently pass an authorized action); deny may have a nil actor (pre-auth/unlinked probe — recording
  # it is the point: deny spikes signal BOLA).
  def self.record!(action:, resource_type:, outcome:, resource_id: nil, denial_reason: nil,
                   policy_version: Authz::PermissionMatrix::MATRIX_VERSION,
                   before: nil, after: nil, request_id: nil, source_ip: nil, user_agent: nil)
    account = Current.account
    actor_id = account&.domain_user_id
    # Fail-CLOSED: only an explicit deny may have a nil actor (pre-auth probe). Anything else — incl. a
    # typo'd outcome (m-4) — REQUIRES a domain actor, so a non-canonical outcome cannot slip an
    # authorized action through actorless.
    if actor_id.nil? && outcome.to_s != "deny"
      raise "AuditLog #{outcome} requires a domain actor (actor_id is nil — unlinked Account?)"
    end

    create!(
      tenant_id: Current.tenant_id, region: account&.organization&.region,
      actor_id: actor_id, actor_account_id: account&.id,
      action: action.to_s, resource_type: resource_type.to_s, resource_id: resource_id,
      outcome: outcome.to_s, denial_reason: denial_reason, policy_version: policy_version,
      before: before, after: after,
      request_id: request_id, source_ip: source_ip, user_agent: user_agent
    )
  end

  # For `rails audit:verify` — recompute the chain hash from the persisted fields (must match chain_hash).
  def expected_chain_hash
    AuditLogHash.compute(canonical_body, prev_chain_hash)
  end

  private

  def assign_chain
    self.ts ||= Time.current
    conn = self.class.connection
    # Serialize concurrent inserts for THIS tenant until the tx commits; UNIQUE(tenant_id,tenant_seq)
    # is the backstop. hashtext maps the uuid → int for the 2-arg advisory lock.
    conn.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_NS}, hashtext(#{conn.quote(tenant_id.to_s)}))")
    prior = self.class.where(tenant_id: tenant_id).order(tenant_seq: :desc).first
    self.tenant_seq = (prior&.tenant_seq || 0) + 1
    self.prev_chain_hash = prior&.chain_hash
    self.chain_hash = AuditLogHash.compute(canonical_body, prev_chain_hash)
  end

  def canonical_body
    AuditLogHash.canonical(
      tenant_id: tenant_id, tenant_seq: tenant_seq, region: region,
      actor_id: actor_id, actor_account_id: actor_account_id,
      action: action, resource_type: resource_type, resource_id: resource_id,
      outcome: outcome, denial_reason: denial_reason, policy_version: policy_version,
      before: before, after: after, ts: ts.utc.iso8601(6)
    )
  end
end
