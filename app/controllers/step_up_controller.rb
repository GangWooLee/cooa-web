# P6 #1 step-up: self-service TOTP enrollment page. The user manages their OWN factor (no resource to
# authorize → skip_authorization). Provisions a secret on first visit; shows the otpauth URI + manual key
# to add to an authenticator app. (Confirm-by-code flow + QR rendering + show-once are Phase 2b polish.)
class StepUpController < ApplicationController
  def show
    skip_authorization
    current_account.provision_totp! unless current_account.totp_enrolled?
    @provisioning_uri = current_account.totp_provisioning_uri
    @secret = current_account.totp_secret
  end
end
