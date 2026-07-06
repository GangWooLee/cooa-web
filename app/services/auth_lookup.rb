# T2 (identity-based tenant resolution) — the login-time identity→tenant DISCOVERY bridge.
#
# accounts + invitations are RLS-protected, so a PRE-login query under cooa_app (no tenant GUC yet) fail-
# CLOSES to 0 rows. To learn which org(s) a just-verified IdP identity belongs to, the flow calls the two
# SECURITY DEFINER functions (migration 20260706000001) — the ONE narrow, minimal-surface cross-tenant read.
# Everything past this point runs under the resolved tenant's RLS tx like any other request.
class AuthLookup
  # A loginable account candidate for a verified identity. `bound` = matched by (provider, subject) — an
  # exact IdP binding; false = an UNBOUND account matched by verified email (a first-login BIND is due).
  Candidate = Struct.new(:account_id, :tenant_id, :org_name, :org_region, :bound, keyword_init: true) do
    def to_param = account_id
    def bound? = bound
  end

  # Candidates for (provider, subject) + — ONLY when the IdP asserted email_verified — the unbound bind
  # candidates matched by email. Passing the email to the function is gated on `email_verified` so an
  # attacker-assertable (unverified) email yields NO first-login candidates (mirrors the old bind gate).
  # Only ACTIVE accounts are returned as loginable (an inactive bound account → 0 candidates → reject).
  def self.account_candidates(provider:, subject:, email:, email_verified:)
    conn = ActiveRecord::Base.connection
    verified_email = email_verified ? email.to_s.presence : nil
    sql = "SELECT account_id, tenant_id, status, bound, org_name, org_region " \
          "FROM auth_lookup_accounts(#{conn.quote(provider.to_s)}, #{conn.quote(subject.to_s)}, #{conn.quote(verified_email)})"
    conn.exec_query(sql, "auth_lookup_accounts").filter_map do |r|
      next unless r["status"] == "active"

      Candidate.new(account_id: r["account_id"], tenant_id: r["tenant_id"], org_name: r["org_name"],
                    org_region: r["org_region"], bound: ActiveModel::Type::Boolean.new.cast(r["bound"]))
    end
  end

  # The tenant of the PENDING invitation with this token digest (UNIQUE → ≤1), or nil. The caller re-opens
  # that tenant's RLS tx and re-loads the full Invitation (RLS re-validates) for display + atomic acceptance.
  def self.invitation_tenant(token_digest)
    conn = ActiveRecord::Base.connection
    conn.select_value("SELECT tenant_id FROM auth_lookup_invitation(#{conn.quote(token_digest.to_s)})")
  end
end
