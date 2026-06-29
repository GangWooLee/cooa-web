# Local account-picker login (Phase 2a-1): sets session[:account_id] from a demo account — NO password.
# Guarded to non-production via config.x.local_login_enabled; production uses the Keycloak OIDC broker
# (Phase 2b), whose callback reuses #create's session seam (reset_session + account_id + token_version).
class SessionsController < ApplicationController
  layout "auth"
  allow_unauthenticated_access only: %i[new create omniauth_callback auth_failure]
  skip_after_action :verify_authorized # sessions are not a Pundit-authorized resource
  before_action :ensure_local_login_enabled, only: [:new, :create]

  def new
    @accounts = Account.active.includes(:user).order(:id)
  end

  def create
    account = Account.active.find_by(id: params[:account_id])
    return redirect_to(new_session_path, alert: "계정을 선택하세요.", status: :see_other) unless account

    reset_session # session fixation 방어 (ADR-003 §7.2)
    session[:account_id] = account.id
    session[:token_version] = account.token_version
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: "로그아웃되었습니다.", status: :see_other
  end

  # OIDC callback (Phase 2b) — converges onto the SAME session seam as #create. The tenant comes from the
  # connection (Current.tenant_id, set by the Authentication concern), NEVER the token's org claim. Demo
  # accounts are matched by email on first login and bound to the IdP subject (roles/User preserved);
  # production gates first login on an invitation (TODO Phase 3).
  def omniauth_callback
    auth = request.env["omniauth.auth"]
    return reject!("인증 정보가 없습니다.") if auth.nil?

    account = Account.find_by(tenant_id: Current.tenant_id, idp_subject: auth.uid) # returning user (bound)
    account ||= bind_first_login(auth)                                             # first login (guarded)
    return reject!("허가되지 않은 계정입니다.") unless account&.active?

    reset_session
    session[:account_id] = account.id
    session[:token_version] = account.token_version
    redirect_to root_path
  end

  def auth_failure
    reject!("인증에 실패했습니다: #{params[:message]}")
  end

  private

  # First OIDC login binds the IdP subject to a PRE-PROVISIONED, UNBOUND account by VERIFIED email only.
  # Defenses (P2 C-1 / ADR-002 §0 BOLA): (1) require the email_verified claim — auth.info.email is
  # otherwise attacker-assertable; (2) bind ONLY an UNBOUND account — idp_subject nil or the local
  # sentinel "local|*" (db/seeds). An account already bound to a REAL IdP subject is NEVER rebound
  # (account-takeover + owner DoS). Single-use invitation gating is Phase 2b.
  def bind_first_login(auth)
    return nil unless oidc_email_verified?(auth)
    email = auth.info&.email
    return nil if email.blank?
    account = Account.active.where(tenant_id: Current.tenant_id, email: email)
                     .where("idp_subject IS NULL OR idp_subject LIKE 'local|%'").first
    account&.update!(idp_subject: auth.uid)
    account
  end

  def oidc_email_verified?(auth)
    raw = auth.extra&.raw_info
    raw && (raw["email_verified"] == true || raw["email_verified"].to_s == "true")
  end

  def reject!(message)
    redirect_to new_session_path, alert: message, status: :see_other
  end

  def ensure_local_login_enabled
    head :not_found unless Rails.configuration.x.local_login_enabled
  end
end
