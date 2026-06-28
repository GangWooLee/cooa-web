# Login identity, SINGLE-TENANT (ADR-002 §5.1 / ADR-003 §13): one account = one tenant.
# Email is UNIQUE PER-TENANT (never global) → blocks cross-tenant enumeration.
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.string :email, null: false
      t.string :display_name
      t.string :status, null: false, default: "invited"   # invited | active | suspended | deprovisioned
      t.boolean :is_cooa_staff, null: false, default: false
      t.integer :token_version, null: false, default: 0    # bump = revoke-all (ADR-003 §3.3)
      t.string :idp_subject                                # Keycloak sub (Phase 2)
      t.string :region
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :accounts, %i[tenant_id email], unique: true, name: "index_accounts_on_tenant_id_and_email"
    add_index :accounts, :tenant_id
    add_check_constraint :accounts,
      "status IN ('invited','active','suspended','deprovisioned')", name: "accounts_status_check"
    add_foreign_key :accounts, :organizations, column: :tenant_id
  end
end
