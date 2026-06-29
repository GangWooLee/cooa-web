# P6 #1 — approval step-up (Phase A: TOTP). accounts hold an encrypted per-account TOTP secret;
# approval_steps persist the signing-moment re-auth evidence (Part-11 §11.50/§11.200) bound to the exact
# reviewed-tuple digest. No new table (single-request TOTP; abandoned attempts are audited as a deny).
# accounts + approval_steps already carry RLS + the cooa_app grant, so new columns inherit both.
class AddStepUpToApprovals < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :totp_secret, :string           # AR-encrypted (encrypts :totp_secret)
    add_column :accounts, :totp_registered_at, :datetime

    add_column :approval_steps, :re_auth_at, :datetime     # when the approver re-authenticated to sign
    add_column :approval_steps, :re_auth_factor, :string   # 'totp' | 'webauthn'(2b) | 'legacy_none'(backfill)
    add_column :approval_steps, :signed_c1_digest, :string # the exact reviewed-tuple digest that was signed
  end
end
