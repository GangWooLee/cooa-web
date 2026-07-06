# Login. Two entry seams converge on ONE session seam (establish_session): the dev/test account-picker
# (#create — no password, guarded to non-production) and the production OIDC/OAuth callback (#omniauth_callback
# via the Keycloak/Google broker). T2 (identity-based tenant): a deployment can host MANY orgs, so the callback
# DISCOVERS which org(s) a verified identity belongs to (SECURITY DEFINER bridge, tenant-less entry) and either
# signs in directly, prompts an org picker (same identity in several orgs), or accepts an invitation — and
# establish_session records session[:tenant_id] so every later request resolves the tenant from the SESSION.
class SessionsController < ApplicationController
  include SessionEstablishment # the shared login seam (establish_session) — also used by OnboardingController
  layout "auth"
  allow_unauthenticated_access only: %i[new create omniauth_callback select_organization auth_failure]
  skip_after_action :verify_authorized # sessions are not a Pundit-authorized resource
  before_action :ensure_local_login_enabled, only: [ :new, :create ]

  def new
    @accounts = Account.active.includes(:user).order(:id) # runs under the dev/test demo picker fallback tenant
  end

  def create
    account = Account.active.find_by(id: params[:account_id])
    return redirect_to(new_session_path, alert: "계정을 선택하세요.", status: :see_other) unless account

    establish_session(account) # dev/test picker: identity = the click; tenant = the account's org
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to new_session_path, notice: "로그아웃되었습니다.", status: :see_other
  end

  # OIDC/OAuth 콜백 — provider 무관 단일 seam(google_oauth2·openid_connect). T2: 로그인 전이라 세션 테넌트가
  # 없다 → tenant-less로 진입해 검증된 신원으로 SECURITY DEFINER 브리지를 통해 계정을 조직 경계 너머로 발견하고
  # 결과 수로 분기한다: 1개=직행 로그인 · 복수(동일 신원·여러 조직)=조직 선택 화면 · 0개=초대 수락(있으면) 또는
  # 온보딩(T3 seam). 토큰의 org claim은 절대 신뢰하지 않는다 — tenant는 발견 결과에서만 온다.
  def omniauth_callback
    auth = request.env["omniauth.auth"]
    return reject!("인증 정보가 없습니다.") if auth.nil?

    invite_raw = session[:invite_token] # 초대 랜딩이 심어둠 — reset 전에 확보(있으면 0계정 폴백에서 소비)
    candidates = AuthLookup.account_candidates(
      provider: auth.provider.to_s, subject: auth.uid,
      email: auth.info&.email, email_verified: oidc_email_verified?(auth)
    )

    case candidates.length
    when 1 then complete_login(candidates.first, provider: auth.provider.to_s, subject: auth.uid, invite_raw: invite_raw)
    when 0 then onboard_without_account(auth, invite_raw)
    else        prompt_organization(candidates, auth, invite_raw)
    end
  end

  # 조직 선택(Slack식) — 콜백이 복수 후보를 찾아 렌더한 목록에서 하나를 고른 POST. 검증된 신원은
  # session[:pending_login](암호화 쿠키 → 위조 불가)에 잠깐 보관됐다가 여기서 재-발견으로 재확인된다:
  # POST된 account_id를 그대로 신뢰하지 않고 반드시 재발견한 후보집합에 속해야 통과한다(권한 상승 차단).
  def select_organization
    pending = session[:pending_login]
    return reject!("세션이 만료되었습니다. 다시 로그인하세요.") if pending.blank?

    candidates = AuthLookup.account_candidates(
      provider: pending["provider"], subject: pending["subject"],
      email: pending["email"], email_verified: pending["verified"]
    )
    chosen = candidates.find { |c| c.account_id == params[:account_id] }
    return reject!("허가되지 않은 선택입니다.") unless chosen

    session.delete(:pending_login)
    complete_login(chosen, provider: pending["provider"], subject: pending["subject"], invite_raw: pending["invite"])
  end

  def auth_failure
    reject!("인증에 실패했습니다: #{params[:message]}")
  end

  private

  # 발견된 계정으로 로그인 완결(1-후보 직행 · 선택 후 공용). 미바인딩 후보(검증 이메일 매칭)면 이 시점에
  # (provider, subject)를 바인딩(과거 bind_first_login 대체). 초대 링크로 왔으면 유령 pending을 소비(재초대
  # 차단 방지). 전부 그 계정의 테넌트 RLS tx 안에서 — 크로스 테넌트 쓰기 불가.
  def complete_login(candidate, provider:, subject:, invite_raw:)
    account = TenantContext.with_tenant(candidate.tenant_id) do
      Current.tenant_id = candidate.tenant_id
      acct = Account.find(candidate.account_id)
      acct.update!(idp_provider: provider, idp_subject: subject) if acct.idp_subject.nil? # first-login bind
      consume_matching_invitation(acct) if invite_raw.present?
      acct
    end
    establish_session(account)
    redirect_to root_path
  end

  # 0계정 분기. 순서(초대가 이긴다): ① 유효 초대 티켓이면 그 조직으로 원자 수락(Phase 3) → 직행 로그인. ②
  # 아니면 **T3 셀프서브 온보딩** — 검증된 이메일이면 신원을 세션에 잠시 심고 /onboarding으로(자기 조직 신설).
  # ③ 미검증 이메일(초대도 없음)은 기존대로 거부(열거 방지).
  def onboard_without_account(auth, invite_raw)
    account = accept_invitation_signup(auth, invite_raw)
    if account&.active?
      establish_session(account)
      return redirect_to root_path
    end
    # 셀프서브 온보딩은 **초대 없이** 온 검증 신원에게만 열린다. 초대 링크로 왔는데 실패한 경우(불일치·만료·회수·
    # 레이스 패배·미검증)는 기존대로 거부 — 초대가 이긴다(기존 분기 순서 보존)·초대 실패가 조용히 남의 조직 대신
    # 엉뚱한 새 조직을 만드는 혼란/토큰 탈취 보상을 막는다. 온보딩은 순수 신규 가입 경로(로그인 화면 → Google)뿐.
    return start_self_serve_onboarding(auth) if invite_raw.blank? && self_serve_eligible?(auth)

    reject!("허가되지 않은 계정입니다.#{dev_reject_hint(auth)}")
  end

  # T3 셀프서브 자격: **Google 소비자 신원 + 검증 이메일**만. 엔터프라이즈 SSO(openid_connect/Keycloak)는
  # 제외 — 그 issuer를 소유한 조직이 이미 존재하므로 SSO 사용자가 새 조직을 자가생성하는 건 무의미하다(미프로비저닝
  # SSO 사용자는 기존대로 거부). 새 소비자 provider가 생기면 이 allowlist에 추가한다.
  SELF_SERVE_PROVIDERS = %w[google_oauth2].freeze

  # Stash ONLY a VERIFIED identity (signed/encrypted session cookie → tamper-resistant; we additionally accept
  # only the IdP-verified email) for the one-screen onboarding, then route there. The org is minted by
  # OnboardingController#create, never here — the callback just carries the identity across the redirect.
  def self_serve_eligible?(auth)
    SELF_SERVE_PROVIDERS.include?(auth.provider.to_s) &&
      oidc_email_verified?(auth) && auth.info&.email.to_s.present?
  end

  def start_self_serve_onboarding(auth)
    session[:pending_signup] = {
      "provider" => auth.provider.to_s, "subject" => auth.uid,
      "email" => auth.info&.email.to_s.downcase, "name" => auth.info&.name.to_s,
      "verified" => oidc_email_verified?(auth) # carry the IdP verified fact (⇢ OnboardingController), like pending_login
    }
    redirect_to new_onboarding_path
  end

  # 복수 후보(동일 신원이 여러 조직의 멤버) → 조직 선택 화면. 검증된 신원만 세션에 잠시 보관했다가
  # select_organization이 재-발견으로 재확인한다. 미바인딩 후보 바인딩은 선택 확정 후 complete_login이 수행.
  def prompt_organization(candidates, auth, invite_raw)
    session[:pending_login] = {
      "provider" => auth.provider.to_s, "subject" => auth.uid, "email" => auth.info&.email,
      "verified" => oidc_email_verified?(auth), "invite" => invite_raw
    }
    @candidates = candidates
    render :organizations
  end

  def oidc_email_verified?(auth)
    raw = auth.extra&.raw_info
    raw && (raw["email_verified"] == true || raw["email_verified"].to_s == "true")
  end

  # 초대-게이트 신규 온보딩(Phase 3): 검증된 이메일 + 유효 티켓 + 초대 email == 검증 email(토큰만 훔쳐선 타
  # Google 계정으로 수락 불가). T2: 초대의 테넌트를 브리지로 해석한 뒤 그 테넌트 tx에서 원자 수락
  # (InvitationAcceptance가 Current.tenant_id를 사용 → 블록 안에서 세팅). 생성/클레임 원자성은 서비스가 담당.
  def accept_invitation_signup(auth, raw)
    return nil if raw.blank?
    return nil unless oidc_email_verified?(auth)
    email = auth.info&.email.to_s.downcase
    return nil if email.blank?

    digest = Invitation.digest(raw)
    tenant_id = AuthLookup.invitation_tenant(digest)
    return nil if tenant_id.blank?

    TenantContext.with_tenant(tenant_id) do
      Current.tenant_id = tenant_id
      invitation = Invitation.pending.find_by(token_digest: digest)
      next nil unless invitation && invitation.email == email

      InvitationAcceptance.call(invitation: invitation, auth: auth)
    end
  end

  # 초대 링크로 왔지만 기존 경로(재방문/bind)로 로그인된 경우: 본인 이메일의 pending 초대를 소비(같은 테넌트
  # 스코프) — 안 하면 유령 pending이 부분 유니크에 걸려 재초대를 막는다. 수락 경로에선 이미 accepted라 no-op.
  def consume_matching_invitation(account)
    invitation = Invitation.pending.find_by(email: account.email.to_s.downcase)
    invitation.update!(accepted_account_id: account.id) if invitation&.claim!
  end

  # 로그인 실패 원인 진단 — **development 전용**(test/prod는 항상 "" 반환 → 열거 방지 유지). tenant-less 콜백에서도
  # 안전하게 동작하도록 브리지로 후보를 조회한다(연결-테넌트 가정 없음).
  def dev_reject_hint(auth)
    return "" unless Rails.env.development?
    email = auth&.info&.email.to_s.downcase
    return " [dev] 이메일 정보 없음" if email.blank?
    return " [dev] email_verified=false (Google Workspace 미검증 도메인?)" unless oidc_email_verified?(auth)

    cands = AuthLookup.account_candidates(provider: auth.provider.to_s, subject: auth.uid, email: email, email_verified: true)
    if cands.empty?
      " [dev] #{email}로 매칭·바인딩 가능한 계정 없음 — `bin/rails auth:link_google[#{email}]` 실행 또는 초대 플로우 사용"
    else
      " [dev] #{email} 후보 #{cands.size}건이 발견되나 로그인 미완 — 서버 로그 확인"
    end
  end

  def reject!(message)
    redirect_to new_session_path, alert: message, status: :see_other
  end

  def ensure_local_login_enabled
    head :not_found unless Rails.configuration.x.local_login_enabled
  end
end
