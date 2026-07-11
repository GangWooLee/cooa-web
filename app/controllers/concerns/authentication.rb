# Phase 2 auth (ADR-003) — IDENTITY-BASED tenant resolution (T2). One deployment can now host MANY orgs, so
# the request tenant is NO LONGER derived from the connection (ENV/constant). Instead the login flow
# (picker / OAuth callback) verifies the identity, discovers the org it belongs to, and stores BOTH
# session[:account_id] and session[:tenant_id]. Every request then:
#   scope_to_tenant  → open the RLS tx with the SESSION tenant (SET LOCAL) — must precede the account load
#   resolve_account  → inside the tx: load the account and RE-CHECK it belongs to the session tenant
#                      (a forged/stale session tenant makes it invisible under RLS ⇒ nil ⇒ reset+login),
#                      then re-check revocation (status/token_version) + idle timeout every request.
# The Account is the authenticated principal; its linked User is the display source (Strategy B).
module Authentication
  extend ActiveSupport::Concern

  IDLE_TIMEOUT = 60.minutes

  included do
    around_action :scope_to_tenant  # open the RLS tx for the session-resolved tenant — precedes the load
    before_action :resolve_account  # inside the tx → accounts is RLS-scoped to the session tenant
    helper_method :current_account, :current_user
  end

  class_methods do
    # Pre-login actions run WITHOUT an account. The tenant they operate under is decided by scope_to_tenant:
    # the dev/test account-picker gets a demo fallback; the OAuth callback + invite landing resolve their own
    # tenant from a verified token (SECURITY DEFINER bridge) and otherwise run tenant-less.
    def allow_unauthenticated_access(**options)
      skip_before_action :resolve_account, **options
    end
  end

  private

  def current_account = Current.account
  def current_user = Current.account&.user # domain person — write-sites & views unchanged (Strategy B)

  # Wrap the request (action + view render) in the SESSION-resolved tenant's RLS context; SET LOCAL clears at
  # tx end. An unauthenticated request carries no tenant and runs tenant-less — the callback/invite landing
  # resolve their own tenant via the auth bridge; the dev/test picker gets a demo fallback (see below).
  def scope_to_tenant(&block)
    Current.tenant_id = resolved_tenant_id
    if Current.tenant_id.present?
      TenantContext.with_tenant(Current.tenant_id, &block)
    else
      yield
    end
  end

  def resolved_tenant_id
    return session[:tenant_id] if session[:tenant_id].present?

    demo_picker_fallback_tenant_id
  end

  # The account-PICKER (dev/test only) lists + selects seeded accounts, so it needs a tenant context while
  # unauthenticated. Every OTHER pre-login path resolves its own tenant (callback/invite landing) or is
  # authenticated. Gated to non-production (config.x.local_login_enabled) so production pre-login is strictly
  # tenant-less. Scoped to sessions#new/#create only — a stray demo context must not bleed into other paths.
  def demo_picker_fallback_tenant_id
    return nil unless Rails.configuration.x.local_login_enabled
    return nil unless controller_name == "sessions" && %w[new create].include?(action_name)

    TenantConfig.fallback_tenant_id
  end

  # Bind the authenticated principal inside the tenant tx. The account MUST belong to the session tenant: a
  # forged/stale session tenant (or an account_id from another org) makes it invisible under this tenant's
  # RLS ⇒ nil, and the explicit tenant equality ALSO catches it on the owner connection (where RLS is
  # bypassed). Revocation (status/token_version) + idle timeout are re-checked every request (ADR-003 §3.3).
  def resolve_account
    return require_login if session[:account_id].blank? || Current.tenant_id.blank?

    # Unscoped read (NO .active): must SEE a suspended/deprovisioned row to detect the revocation transition.
    # Preload :user — the sidebar renders current_account.name on every authenticated page and Account#name
    # falls back to the linked user's name (display_name mostly NULL), so eager-load it here to avoid a
    # per-request `users WHERE id=N` single-row lazy load. Revocation checks read account columns only.
    account = Account.includes(:user).find_by(id: session[:account_id])
    return reset_and_require_login unless live_session_for?(account)

    Current.account = account
    session[:last_seen] = Time.current.to_i
  end

  def live_session_for?(account)
    account.present? &&
      account.tenant_id == Current.tenant_id &&            # identity re-check (T2) — same-tenant principal
      account.active? &&                                   # revocation: suspend / deprovision
      account.token_version == session[:token_version] &&  # revocation: logout-everywhere / role change
      !session_expired?                                    # idle timeout
  end

  def session_expired?
    (last = session[:last_seen]).present? && Time.current.to_i - last.to_i > IDLE_TIMEOUT.to_i
  end

  def reset_and_require_login
    reset_session
    require_login
  end

  def require_login
    redirect_to new_session_path, alert: "로그인이 필요합니다.", status: :see_other
  end
end
