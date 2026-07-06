# Self-serve signup = atomic organization bootstrap (T3). The identity-twin of InvitationAcceptance, but
# there is NO pre-existing tenant: a brand-new VERIFIED Google identity mints its OWN org. Caller guarantees
# (OnboardingController): the email is IdP-verified and there is no account for this identity anywhere.
#
# Everything commits inside ONE transaction opened on the NEW tenant's RLS context (with_tenant(org_id) sets
# app.current_tenant_id BEFORE the first INSERT, so organizations' `id = GUC` WITH CHECK and every scoped
# table's `tenant_id = GUC` WITH CHECK pass). Any failure rolls the whole org back — never a half-born tenant.
#
# Order mirrors the FK graph: org → user(person) → account(+owner binding) → owner grant → first workspace →
# audit. The audit actor is the just-created owner (User exists → domain actor present → fail-closed passes).
class OrganizationBootstrap
  Result = Struct.new(:account, :workspace, keyword_init: true)

  # Per-IDENTITY advisory-lock namespace — distinct from the per-tenant chain locks (AuditLog 0x4155,
  # LastOwnerGuard 0x4C4F) so the 2-arg keyspaces never alias. "OB" = 0x4F42.
  ADVISORY_NS = 0x4F42

  AVATAR_PALETTE = InvitationAcceptance::AVATAR_PALETTE
  # Self-serve signup carries no market signal yet (the owner picks none here). A required, changeable
  # placeholder — region drives audit stamping + screening market, both meaningless before any product exists.
  DEFAULT_REGION = "JP"

  def self.call(provider:, subject:, email:, name:, workspace_name:)
    email   = email.to_s.downcase
    ws_name = workspace_name.to_s.strip
    return nil if email.blank? || ws_name.blank?

    org_id = SecureRandom.uuid
    result = nil
    existing = nil
    TenantContext.with_tenant(org_id) do
      Current.tenant_id = org_id

      # Concurrency invariant (double-POST / stale re-POST). Two requests for the SAME identity could each
      # pass the controller's pre-lock re-discovery (0 accounts) and both mint a duplicate org. Serialize
      # them on a per-IDENTITY advisory XACT lock and RE-DISCOVER *inside* it: the lock is held until this
      # tx ends, so a loser BLOCKS here until the winner commits, then observes the winner's now-committed
      # BOUND account (auth_lookup_accounts returns bound (provider,subject) matches regardless of the
      # email_verified gate) and converges on it — NEVER a second org. Only an EMPTY candidate set mints.
      # Mirrors AuditLog#assign_chain's 2-arg lock + quoting; the distinct NS keeps the keyspace disjoint
      # (hashtext is 32-bit, so a bare 1-arg lock could collide with the per-tenant chain locks).
      conn = ActiveRecord::Base.connection
      conn.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_NS}, hashtext(#{conn.quote("#{provider}:#{subject}")}))")
      existing = AuthLookup.account_candidates(
        provider: provider, subject: subject, email: email, email_verified: true
      ).first
      next if existing # a concurrent request already onboarded this identity → converge, do not duplicate

      # Internal org label = the email domain — a stable, non-user-facing handle (the org is never surfaced
      # to the founder by name in the self-serve product; workspaces are the unit users see).
      Organization.create!(id: org_id, name: org_label(email), region: DEFAULT_REGION)

      # User = the domain "person" (SoD actor_id + audit fail-closed need it). role is display-only (real
      # authz = the owner RoleAssignment below). Same palette/naming convention as InvitationAcceptance.
      user = User.create!(
        name: name.to_s.presence || email.split("@").first, email: email, role: "pm",
        avatar_color: AVATAR_PALETTE[email.sum % AVATAR_PALETTE.size]
      )
      # Bind (provider, subject) on creation — no separate first-login bind. (tenant,email) + (tenant,provider,
      # subject) UNIQUE are the backstops.
      account = Account.create!(
        tenant_id: org_id, user: user, email: email, status: "active",
        idp_provider: provider.to_s, idp_subject: subject.to_s
      )
      # The founding grant is TENANT-WIDE owner (owner_must_be_tenant_wide + the DB CHECK). Self-granted.
      RoleAssignment.create!(
        account: account, tenant_id: org_id, role_key: "owner", scope_type: "tenant",
        granted_by: account.id, granted_at: Time.current
      )
      workspace = Workspace.create!(tenant_id: org_id, name: ws_name, position: 1)

      # Audit the tenant's genesis. Actor = the new owner (Current.account set → domain actor present).
      Current.account = account
      AuditLog.record!(action: "organization.bootstrap", resource_type: "Organization", resource_id: nil,
                       outcome: "allow",
                       after: { organization_id: org_id, email: email, workspace_id: workspace.id,
                                workspace_name: ws_name })
      result = Result.new(account: account, workspace: workspace)
    end
    # An in-lock re-discovery (existing) is an AuthLookup::Candidate the caller signs into (idempotent
    # converge); a fresh mint is a Result. Nil only on genuine failure (rescue below).
    existing || result
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("[onboarding] bootstrap failed for #{email}: #{e.class}: #{e.message.lines.first&.strip}")
    nil
  end

  # The email domain (or the whole address if malformed) as the internal org handle.
  def self.org_label(email)
    email.split("@").last.presence || email
  end
end
