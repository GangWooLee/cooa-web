# Connection→tenant resolution (ADR-003 §2.1/§2.3). The tenant is derived from the CONNECTION, never a
# client claim — and NEVER by querying `organizations` (it is itself RLS-protected, policy `id = GUC`, so
# under cooa_app a pre-auth org query fail-closes). SI silo = one tenant per deployment via ENV; the local
# demo = a single fixed tenant uuid (shared by seeds, test_helper, the auth concern, and the e2e smoke).
module TenantConfig
  DEMO_TENANT_ID = "11111111-1111-1111-1111-111111111111".freeze

  module_function

  def connection_tenant_id
    raise "COOA_TENANT_ID required in production" if Rails.env.production? && ENV["COOA_TENANT_ID"].blank?

    ENV["COOA_TENANT_ID"].presence || DEMO_TENANT_ID
  end
end
