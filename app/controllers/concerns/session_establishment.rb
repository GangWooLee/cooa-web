# The ONE login seam (ADR-003 §7.2). Both the login controller (picker/OAuth) and the self-serve onboarding
# controller converge here to open an authenticated session: reset_session first (session-fixation defense),
# then stamp account + tenant + token_version. session[:tenant_id] is the source of T2 request-tenant
# resolution (Authentication#resolved_tenant_id); session[:token_version] gates revocation every request.
module SessionEstablishment
  extend ActiveSupport::Concern

  private

  def establish_session(account)
    reset_session
    session[:account_id] = account.id
    session[:tenant_id] = account.tenant_id
    session[:token_version] = account.token_version
  end
end
