require Rails.root.join("lib/tenant_rls").to_s

# Phase 0b M1 — products (tree root). Self-referential parent_id gets a SAME-TENANT composite FK
# so a product can never point at a parent in another tenant (FK checks bypass RLS otherwise).
class AddTenantToProducts < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_column :products, :tenant_id, :uuid
    # Backfill existing rows to a single demo org (only when rows exist → fresh DBs stay org-free; seeds owns the demo org).
    if select_value("SELECT COUNT(*) FROM products WHERE tenant_id IS NULL").to_i.positive?
      backfill_tenant!("products", "'#{seed_org_id}'")
    end
    change_column_null :products, :tenant_id, false
    add_index :products, :tenant_id

    # Parent key for composite FKs (this table is referenced by components, members, properties, and itself).
    execute "ALTER TABLE products ADD CONSTRAINT products_tenant_id_id_key UNIQUE (tenant_id, id)"

    # Replace the single self-ref FK with a same-tenant composite FK.
    remove_foreign_key :products, :products, column: :parent_id
    execute <<~SQL
      ALTER TABLE products
        ADD CONSTRAINT products_parent_tenant_fkey
        FOREIGN KEY (tenant_id, parent_id) REFERENCES products (tenant_id, id)
    SQL

    enable_tenant_rls!("products")
  end

  def down
    disable_tenant_rls!("products")
    execute "ALTER TABLE products DROP CONSTRAINT IF EXISTS products_parent_tenant_fkey"
    add_foreign_key :products, :products, column: :parent_id
    execute "ALTER TABLE products DROP CONSTRAINT IF EXISTS products_tenant_id_id_key"
    remove_column :products, :tenant_id
  end
end
