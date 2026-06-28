# Phase 2a-1 (Strategy B) — link the auth identity (Account, uuid) to the demo person (User, bigint).
# Account = login identity; User stays the domain "person" (FK target of owner_id / *_by_id) and the
# display source. AccessContext#actor_id bridges Account→user_id so identity-SoD compares in the bigint
# space (else requested_by_id(bigint) != actor_id(uuid) is always true → self-approval fail-open).
# Runs as the owner (FK target users is a global, non-tenant table → no composite FK needed).
class AddUserToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounts, :user, foreign_key: true, null: true
  end
end
