# Tenant availability invariant (P6 #3): a tenant must ALWAYS retain >=1 active owner. Enforced as a
# MODEL invariant (Account + RoleAssignment callbacks) — there is no single mutation entrypoint, so a
# controller guard would be vacuous. REFUSE-only: the offending mutation raises and its tx rolls back.
# (Zero-owner recovery, if it ever happens, is the owner-recovery break-glass path — P6 #2.)
module LastOwnerGuard
  ADVISORY_NS = 0x4C4F # "LO" — distinct from AuditLog's 0x4155 chain lock
  Error = Class.new(StandardError)

  module_function

  # Raise unless the tenant still has an active owner OTHER than losing_account_id (the account this
  # mutation removes from the owner set). Serializes concurrent demotions per-tenant (advisory xact lock)
  # so two owners cannot each observe the other and both proceed. Runs inside the mutation's transaction.
  def ensure_owner_remains!(tenant_id, losing_account_id)
    return if tenant_id.blank?
    conn = RoleAssignment.connection
    conn.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_NS}, hashtext(#{conn.quote(tenant_id.to_s)}))")
    return if other_active_owners?(tenant_id, losing_account_id)
    raise Error, "마지막 owner는 정지·강등·제거할 수 없습니다 (테넌트에 active owner가 최소 1명 남아야 합니다)."
  end

  def other_active_owners?(tenant_id, losing_account_id)
    RoleAssignment.active
                  .where(tenant_id: tenant_id, role_key: "owner", scope_id: nil)
                  .joins(:account).where(accounts: { status: "active" })
                  .where.not(account_id: losing_account_id)
                  .exists?
  end
end
