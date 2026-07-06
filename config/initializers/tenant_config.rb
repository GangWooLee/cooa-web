# Tenant resolution helpers. Since T2 the REQUEST tenant is IDENTITY-based (session, set by the login flow
# after verifying identity — see Authentication#scope_to_tenant), never a connection/ENV constant. Two
# narrow fallbacks remain, both NEVER by querying `organizations` (itself RLS-protected, policy `id = GUC`):
#   * connection_tenant_id — for NON-request CLI contexts (auth.rake google-link tasks) that need "the" demo
#     / SI-silo tenant to open a TenantContext. Raises in production if COOA_TENANT_ID is unset (no guess).
#   * fallback_tenant_id — the dev/test account-PICKER's tenant while unauthenticated (so seeds/smoke list
#     accounts). Returns nil in production → production pre-login is strictly tenant-less.
module TenantConfig
  DEMO_TENANT_ID = "11111111-1111-1111-1111-111111111111".freeze

  module_function

  def connection_tenant_id
    raise "COOA_TENANT_ID required in production" if Rails.env.production? && ENV["COOA_TENANT_ID"].blank?

    ENV["COOA_TENANT_ID"].presence || DEMO_TENANT_ID
  end

  # Dev/test-only: the seeded tenant the account-picker operates under before login. nil in production.
  def fallback_tenant_id
    return nil if Rails.env.production?

    ENV["COOA_TENANT_ID"].presence || DEMO_TENANT_ID
  end
end
