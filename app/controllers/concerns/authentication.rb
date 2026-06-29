# Phase 2a auth (ADR-003). The Account is the authenticated principal; its linked User is the domain
# person / display source (Strategy B). The tenant is resolved from the CONNECTION (TenantConfig) — never
# the account's claim — and set BEFORE the RLS transaction opens, so account lookups run tenant-scoped
# (under cooa_app a pre-context query on the RLS-protected accounts table fail-closes → 0 rows). Revocation
# (token_version/status) is checked every request.
module Authentication
  extend ActiveSupport::Concern

  IDLE_TIMEOUT = 60.minutes

  included do
    before_action :set_connection_tenant   # from TenantConfig (ENV/constant) — no DB query
    around_action :scope_to_tenant          # open the RLS tx (SET LOCAL) — must precede account lookups
    before_action :resolve_account          # inside the tx → accounts is RLS-scoped to this tenant
    before_action :validate_tenant_match    # defense: the account must belong to the connection tenant
    before_action :verify_revocation
    helper_method :current_account, :current_user
  end

  class_methods do
    # Pre-login actions (SessionsController#new/#create) KEEP the tenant context (so the picker can query
    # accounts within this tenant) and skip only the authentication steps.
    def allow_unauthenticated_access(**options)
      skip_before_action :resolve_account, **options
      skip_before_action :validate_tenant_match, **options
      skip_before_action :verify_revocation, **options
    end
  end

  private

  def current_account = Current.account
  def current_user = Current.account&.user # domain person — write-sites & views unchanged (Strategy B)

  # Tenant from the connection (SI silo ENV / demo constant), NOT the account. Set before scope_to_tenant.
  def set_connection_tenant
    Current.tenant_id = TenantConfig.connection_tenant_id
  end

  # Wrap the request (action + view render) in the tenant's RLS context; SET LOCAL clears at tx end.
  def scope_to_tenant(&block)
    TenantContext.with_tenant(Current.tenant_id, &block)
  end

  def resolve_account
    Current.account = Account.active.find_by(id: session[:account_id])
    return require_login unless Current.account

    if session_expired?
      reset_session
      return require_login
    end
    session[:last_seen] = Time.current.to_i
  end

  def session_expired?
    (last = session[:last_seen]).present? && Time.current.to_i - last.to_i > IDLE_TIMEOUT.to_i
  end

  # The signed-in account must belong to the connection-resolved tenant — a cookie carrying an account_id
  # from another tenant must never be honored.
  def validate_tenant_match
    return if Current.account.nil? || Current.account.tenant_id == Current.tenant_id

    Rails.logger.warn("[auth][tenant-mismatch] account=#{Current.account.id} tenant=#{Current.tenant_id}")
    reset_session
    require_login
  end

  # Per-request revocation (ADR-003 §3.3): re-read inside the tenant tx; a status change or token_version
  # bump (suspend/deprovision/role-change/logout-everywhere) invalidates the live session immediately.
  def verify_revocation
    fresh = Account.find_by(id: Current.account.id)
    return if fresh&.active? && fresh.token_version == session[:token_version]

    reset_session
    require_login
  end

  def require_login
    redirect_to new_session_path, alert: "로그인이 필요합니다.", status: :see_other
  end
end
