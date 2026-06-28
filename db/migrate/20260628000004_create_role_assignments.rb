# Scoped role grants (ADR-002 §5.2). Replaces the demo's single User.role enum.
# UNIQUE NULLS NOT DISTINCT prevents duplicate grants when scope_id/market are NULL (PG15+).
# Intentionally NO unique on (scope_id, role_key) — multiple people may hold the same role on one scope.
class CreateRoleAssignments < ActiveRecord::Migration[8.1]
  ROLE_KEYS = %w[owner brand_admin ra_reviewer approver assignee contributor viewer external_collaborator].freeze

  def change
    create_table :role_assignments, id: :uuid do |t|
      t.uuid :tenant_id, null: false
      t.uuid :account_id, null: false
      t.string :role_key, null: false
      t.string :scope_type, null: false, default: "tenant"  # tenant | product | component
      t.uuid :scope_id                                       # NULL = tenant-wide
      t.string :market                                       # JP | CN | US | NULL (regional gating)
      t.uuid :granted_by
      t.datetime :granted_at, null: false, default: -> { "now()" }
      t.datetime :expires_at
      t.timestamps
    end
    add_index :role_assignments, %i[tenant_id account_id role_key scope_id market],
      unique: true, nulls_not_distinct: true, name: "uniq_role_assignment"
    add_index :role_assignments, %i[tenant_id account_id]
    add_check_constraint :role_assignments,
      "role_key IN (#{ROLE_KEYS.map { |k| "'#{k}'" }.join(',')})", name: "role_assignments_role_key_check"
    add_check_constraint :role_assignments,
      "scope_type IN ('tenant','product','component')", name: "role_assignments_scope_type_check"
    add_foreign_key :role_assignments, :accounts, column: :account_id
    add_foreign_key :role_assignments, :organizations, column: :tenant_id
  end
end
