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

  # OIDC/OAuth 콜백 (provider 무관 단일 seam: google_oauth2·openid_connect) — #create와 동일 세션
  # seam으로 수렴. tenant는 connection(Current.tenant_id)에서, 토큰의 org claim은 절대 신뢰 안 함.
  # subject 매칭은 (provider, uid) 쌍 — provider별 subject 네임스페이스 분리(Google sub ≠ KC sub).
  # 최초 로그인은 검증된 이메일로 미바인딩 계정에 link; production 신규 온보딩은 invitation 게이트(Phase 3).
  def omniauth_callback
    auth = request.env["omniauth.auth"]
    return reject!("인증 정보가 없습니다.") if auth.nil?

    invite_raw = session[:invite_token] # reset_session 전에 확보(초대 랜딩이 심어둠 — 있으면 3번째 폴백)
    account = Account.find_by(tenant_id: Current.tenant_id,
                              idp_provider: auth.provider.to_s, idp_subject: auth.uid) # returning (bound)
    account ||= bind_first_login(auth)                                                 # first login (guarded)
    account ||= accept_invitation_signup(auth, invite_raw)                             # invitation-gated 신규(Phase 3)
    return reject!("허가되지 않은 계정입니다.") unless account&.active?

    consume_matching_invitation(account) if invite_raw.present? # bind 승리 시 유령 pending 소비(재초대 차단 방지)

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
  # otherwise attacker-assertable; (2) bind ONLY an UNBOUND account (idp_subject IS NULL) — one already
  # bound to a real subject is NEVER rebound (account-takeover + owner DoS). idp_subject holds ONLY real
  # IdP subjects (no sentinel), so a crafted auth.uid cannot collide with a seeded row. Invitation = 2b.
  def bind_first_login(auth)
    return nil unless oidc_email_verified?(auth)
    email = auth.info&.email
    return nil if email.blank?
    account = Account.active.find_by(tenant_id: Current.tenant_id, email: email, idp_subject: nil)
    account&.update!(idp_provider: auth.provider.to_s, idp_subject: auth.uid)
    account
  end

  def oidc_email_verified?(auth)
    raw = auth.extra&.raw_info
    raw && (raw["email_verified"] == true || raw["email_verified"].to_s == "true")
  end

  # 초대-게이트 신규 온보딩(Phase 3): 검증된 이메일 + 유효 티켓 + **초대 email == 검증 email**(토큰만
  # 훔쳐선 타 Google 계정으로 수락 불가). 생성/클레임 원자성은 InvitationAcceptance가 담당.
  def accept_invitation_signup(auth, raw)
    return nil if raw.blank?
    return nil unless oidc_email_verified?(auth)
    email = auth.info&.email.to_s.downcase
    return nil if email.blank?
    invitation = Invitation.pending.find_by(token_digest: Invitation.digest(raw))
    return nil unless invitation && invitation.email == email
    InvitationAcceptance.call(invitation: invitation, auth: auth)
  end

  # 초대 링크로 왔지만 기존 경로(재방문/bind)로 로그인된 경우: 본인 이메일의 pending 초대를 소비 —
  # 안 하면 유령 pending이 부분 유니크에 걸려 재초대를 막는다. 수락 경로에선 이미 accepted라 no-op.
  def consume_matching_invitation(account)
    invitation = Invitation.pending.find_by(email: account.email.to_s.downcase)
    invitation.update!(accepted_account_id: account.id) if invitation&.claim!
  end

  def reject!(message)
    redirect_to new_session_path, alert: message, status: :see_other
  end

  def ensure_local_login_enabled
    head :not_found unless Rails.configuration.x.local_login_enabled
  end
end
