# Tenant root. An organization IS the tenant (ADR-002 §5.1). Its own `id` is the tenant key.
class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :region, null: false                                   # JP | CN | US (data residency axis)
      t.string :billing_tier, null: false, default: "starter"         # starter | professional | enterprise | custom
      t.boolean :impersonation_opt_out, null: false, default: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_check_constraint :organizations, "region IN ('JP','CN','US')", name: "organizations_region_check"
    add_check_constraint :organizations,
      "billing_tier IN ('starter','professional','enterprise','custom')",
      name: "organizations_billing_tier_check"
  end
end
