# Phase 2a-1 authentication (ADR-003). The Account is the authenticated principal; its linked User is
# the domain person / display source (Strategy B). Tenant is SERVER-resolved from the account — never a
# client claim (ADR-002 §7 / ADR-003 §2.1). Revocation (token_version/status) is checked every request.
module Authentication
  extend ActiveSupport::Concern

  IDLE_TIMEOUT = 60.minutes

  included do
    before_action :resolve_account
    before_action :set_current_tenant
    around_action :scope_to_tenant
    before_action :verify_revocation
    helper_method :current_account, :current_user
  end

  class_methods do
    # Pre-login actions (SessionsController#new/#create) opt out of the auth gate.
    def allow_unauthenticated_access(**options)
      skip_before_action :resolve_account, **options
      skip_before_action :set_current_tenant, **options
      skip_around_action :scope_to_tenant, **options
      skip_before_action :verify_revocation, **options
    end
  end

  private

  def current_account = Current.account
  def current_user = Current.account&.user # domain person — write-sites & views unchanged (Strategy B)

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

  # From the authenticated account only — runs before scope_to_tenant opens the RLS transaction.
  def set_current_tenant
    Current.tenant_id = Current.account&.tenant_id
  end

  # Wrap the request (action + view render) in the tenant's RLS context; SET LOCAL clears at tx end.
  def scope_to_tenant(&block)
    TenantContext.with_tenant(Current.tenant_id, &block)
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
