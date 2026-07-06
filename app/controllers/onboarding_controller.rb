# Self-serve signup onboarding (T3) — the one-screen "name your first workspace" step for a brand-new
# VERIFIED Google identity the OAuth callback could NOT resolve to any account. The callback stashes the
# verified identity in session[:pending_signup] and routes here; #create mints the org atomically.
#
# Pre-account, so it runs like the login/invite-landing controllers: unauthenticated + not a Pundit resource,
# and tenant-LESS (scope_to_tenant finds no session tenant → yields without a GUC). The bootstrap opens its
# OWN tenant tx (OrganizationBootstrap → TenantContext.with_tenant(new_org_id)).
class OnboardingController < ApplicationController
  include SessionEstablishment
  layout "auth"
  allow_unauthenticated_access only: %i[new create]
  skip_after_action :verify_authorized # pre-auth screen — not a Pundit-authorized resource (as sessions)

  before_action :require_pending_signup

  def new
    @suggested_name = default_workspace_name
  end

  def create
    # Idempotency: re-discover the identity FIRST. If an account now exists (a double-click's winning request
    # already committed, or a stale re-POST), sign into it instead of minting a second org. Same re-discovery
    # defense as SessionsController#select_organization — the raw pending identity is never trusted blindly.
    if (candidate = already_onboarded_candidate)
      return sign_in_discovered(candidate)
    end

    name = params[:workspace_name].to_s.strip
    if name.blank?
      flash.now[:alert] = "작업실 이름을 입력해 주세요."
      @suggested_name = default_workspace_name
      return render :new, status: :unprocessable_entity
    end

    pending = session[:pending_signup]
    result = OrganizationBootstrap.call(
      provider: pending["provider"], subject: pending["subject"],
      email: pending["email"], name: pending["name"], workspace_name: name
    )
    # The bootstrap re-discovers the identity UNDER an advisory lock: it returns a Candidate when a
    # concurrent request won the race (converge to sign-in — same contract as the pre-lock check above),
    # a Result when it minted, or nil on genuine failure.
    return sign_in_discovered(result) if result.is_a?(AuthLookup::Candidate)
    unless result
      flash.now[:alert] = "가입을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요."
      @suggested_name = name
      return render :new, status: :unprocessable_entity
    end

    establish_session(result.account) # reset_session consumes pending_signup + opens the authenticated session
    redirect_to workspace_path(result.workspace), notice: "환영합니다! 첫 작업실이 준비되었어요."
  end

  private

  # Onboarding is gated on a VERIFIED pending signup. The stash carries the IdP `verified` fact (set by
  # SessionsController#start_self_serve_onboarding) so this controller trusts the DATA, not an assumption:
  # a missing/false flag (stale or tampered cookie) is treated as an expired session → back to login.
  def require_pending_signup
    pending = session[:pending_signup]
    return if pending.present? && pending["verified"]

    redirect_to new_session_path, alert: "가입 세션이 만료되었습니다. 다시 로그인해 주세요.", status: :see_other
  end

  # Re-discover loginable candidates for the stashed identity (verified email → also unbound bind candidates).
  # Non-empty ⇒ the identity is ALREADY onboarded → the idempotent sign-in path (no second org).
  def already_onboarded_candidate
    pending = session[:pending_signup]
    candidates = AuthLookup.account_candidates(
      provider: pending["provider"], subject: pending["subject"],
      email: pending["email"], email_verified: pending["verified"] # data-carried (require_pending_signup gates true)
    )
    candidates.one? ? candidates.first : nil
  end

  # Sign into an already-existing account (idempotent re-submit). Load it inside its own tenant tx so the read
  # is RLS-scoped, then hand off to the shared login seam.
  def sign_in_discovered(candidate)
    account = TenantContext.with_tenant(candidate.tenant_id) do
      Current.tenant_id = candidate.tenant_id
      Account.find(candidate.account_id)
    end
    establish_session(account)
    redirect_to root_path, notice: "이미 가입된 계정으로 로그인했습니다."
  end

  def default_workspace_name
    local = session[:pending_signup]&.dig("name").to_s.strip
    local = session[:pending_signup]&.dig("email").to_s.split("@").first.to_s if local.blank?
    local.blank? ? "" : "#{local}님의 작업실"
  end
end
