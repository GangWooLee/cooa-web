# T2 (identity-based tenant resolution). Multi-org coexistence in ONE deployment means the login flow can
# no longer derive the tenant from the connection (ENV/constant) — it must DISCOVER which org(s) an
# authenticated identity belongs to. But `accounts`/`invitations` are RLS-protected: under cooa_app with no
# tenant GUC a pre-login lookup fail-CLOSES to 0 rows (correct for isolation, useless for discovery). These
# two SECURITY DEFINER functions are the ONE narrow, minimal-surface bridge that runs with the owner's
# privileges (which bypass RLS) to resolve identity→tenant, returning the MINIMUM columns the callback needs.
#
# SECURITY DEFINER hardening (standard defenses):
#   * `SET search_path = pg_catalog, pg_temp` — an attacker cannot shadow `accounts`/`organizations`/`lower`
#     with objects in a writable schema (pg_temp is searched LAST; all refs are schema-qualified anyway).
#   * EXECUTE revoked from PUBLIC, granted only to cooa_app (the runtime). structure.sql strips GRANTs
#     (pg_dump -x) so cooa.rake#grant_app re-applies the lockdown after a schema load — R8 classified there.
#   * Returns only account_id/tenant_id/status/org label — never token_version, email, or other columns.
#
# OWNERSHIP REQUIREMENT (prod cutover — docs/prod-cutover.md): the function must be owned by a role that
# bypasses RLS (superuser, or a role with BYPASSRLS). dev/test load structure.sql as the superuser owner, so
# this holds; a production cutover must create these as such an owner or the cross-tenant discovery fails
# CLOSED (0 candidates → login rejected), never OPEN.
class AddAuthLookupFunctions < ActiveRecord::Migration[8.1]
  def up
    # R4 safety_assured: CREATE FUNCTION is a catalog insert — it takes NO lock on any table and touches no
    # rows. strong_migrations can't introspect raw execute so it blocks unconditionally; assert the safety.
    safety_assured do
      # (1) accounts discovery. Branch A = exact IdP binding (provider, subject), ANY status (the caller
      #     applies the active? gate + the "already bound to another subject → never rebind" invariant is
      #     preserved because branch B only matches UNBOUND rows). Branch B = first-login bind candidates:
      #     UNBOUND (idp_subject IS NULL) + ACTIVE + email match. The caller passes p_email ONLY when the IdP
      #     asserted email_verified, so an unverified email yields NO branch-B candidates (mirrors the old
      #     bind_first_login email_verified gate). `bound` tells the caller whether a first-login bind is due.
      execute <<~SQL
        CREATE FUNCTION public.auth_lookup_accounts(p_provider text, p_subject text, p_email text)
          RETURNS TABLE (account_id uuid, tenant_id uuid, status text, bound boolean, org_name text, org_region text)
          LANGUAGE sql
          STABLE
          SECURITY DEFINER
          SET search_path = pg_catalog, pg_temp
          AS $func$
            SELECT a.id, a.tenant_id, a.status::text, true, o.name, o.region
            FROM public.accounts a
            JOIN public.organizations o ON o.id = a.tenant_id
            WHERE a.idp_provider = p_provider AND a.idp_subject = p_subject
            UNION
            SELECT a.id, a.tenant_id, a.status::text, false, o.name, o.region
            FROM public.accounts a
            JOIN public.organizations o ON o.id = a.tenant_id
            WHERE a.idp_subject IS NULL
              AND a.status = 'active'
              AND p_email IS NOT NULL AND p_email <> ''
              AND lower(a.email) = lower(p_email);
          $func$;
      SQL

      # (2) invitation discovery. Resolve a PENDING invite's tenant by token digest (UNIQUE → ≤1 row). The
      #     caller then re-opens that tenant's RLS tx and loads the full Invitation (RLS re-validates) for
      #     display + acceptance. Only tenant_id/id leave the bypass; email/scope stay behind RLS.
      execute <<~SQL
        CREATE FUNCTION public.auth_lookup_invitation(p_token_digest text)
          RETURNS TABLE (invitation_id uuid, tenant_id uuid)
          LANGUAGE sql
          STABLE
          SECURITY DEFINER
          SET search_path = pg_catalog, pg_temp
          AS $func$
            SELECT i.id, i.tenant_id
            FROM public.invitations i
            WHERE i.token_digest = p_token_digest
              AND i.accepted_at IS NULL
              AND i.revoked_at IS NULL
              AND i.expires_at > now();
          $func$;
      SQL

      # Lock down the bypass: no PUBLIC execute, only cooa_app (owner implicitly retains it). structure.sql
      # strips these GRANTs → cooa.rake#grant_app re-applies them (mirrors the RLS table-grant pattern).
      %w[auth_lookup_accounts(text,text,text) auth_lookup_invitation(text)].each do |sig|
        execute "REVOKE ALL ON FUNCTION public.#{sig} FROM PUBLIC"
        execute "GRANT EXECUTE ON FUNCTION public.#{sig} TO cooa_app"
      end
    end
  end

  def down
    safety_assured do
      execute "DROP FUNCTION IF EXISTS public.auth_lookup_accounts(text, text, text)"
      execute "DROP FUNCTION IF EXISTS public.auth_lookup_invitation(text)"
    end
  end
end
