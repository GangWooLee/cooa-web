# Active Record Encryption keys (for accounts.totp_secret — P6 #1 step-up). Prod MUST supply them via ENV
# (fail-fast, mirrors config/database.yml); dev/test use fixed local values. Never commit real prod keys.
enc = Rails.application.config.active_record.encryption
prod = Rails.env.production?
enc.primary_key = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY") do
  prod ? raise("AR_ENCRYPTION_PRIMARY_KEY required in production") : "dev_ar_primary_key_change_me_0123456789"
end
enc.deterministic_key = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY") do
  prod ? raise("AR_ENCRYPTION_DETERMINISTIC_KEY required in production") : "dev_ar_deterministic_key_chg_0123456789"
end
enc.key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT") do
  prod ? raise("AR_ENCRYPTION_KEY_DERIVATION_SALT required in production") : "dev_ar_key_deriv_salt_change_0123456789"
end
