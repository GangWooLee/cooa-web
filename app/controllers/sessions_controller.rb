# Local account-picker login (Phase 2a-1): sets session[:account_id] from a demo account — NO password.
# Guarded to non-production via config.x.local_login_enabled; production uses the Keycloak OIDC broker
# (Phase 2b), whose callback reuses #create's session seam (reset_session + account_id + token_version).
class SessionsController < ApplicationController
  layout "auth"
  allow_unauthenticated_access only: [:new, :create]
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

  private

  def ensure_local_login_enabled
    head :not_found unless Rails.configuration.x.local_login_enabled
  end
end
