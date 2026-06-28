require Rails.root.join("lib/tenant_rls").to_s

# Phase 0b M2 — direct children of products. tenant_id derived from the parent product.
class AddTenantToProductChildren < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_tenant_column!("components", "(SELECT p.tenant_id FROM products p WHERE p.id = components.product_id)", parent_unique: true)
    remove_foreign_key :components, :products
    composite_fk!("components", "product_id", "products", name: "components_product_tenant_fkey")
    enable_tenant_rls!("components")

    add_tenant_column!("product_members", "(SELECT p.tenant_id FROM products p WHERE p.id = product_members.product_id)")
    remove_foreign_key :product_members, :products
    composite_fk!("product_members", "product_id", "products", name: "product_members_product_tenant_fkey")
    enable_tenant_rls!("product_members")

    add_tenant_column!("product_properties", "(SELECT p.tenant_id FROM products p WHERE p.id = product_properties.product_id)")
    remove_foreign_key :product_properties, :products
    composite_fk!("product_properties", "product_id", "products", name: "product_properties_product_tenant_fkey")
    enable_tenant_rls!("product_properties")
  end

  def down
    %w[components product_members product_properties].each { |t| disable_tenant_rls!(t) }
    execute "ALTER TABLE components DROP CONSTRAINT IF EXISTS components_product_tenant_fkey"
    execute "ALTER TABLE product_members DROP CONSTRAINT IF EXISTS product_members_product_tenant_fkey"
    execute "ALTER TABLE product_properties DROP CONSTRAINT IF EXISTS product_properties_product_tenant_fkey"
    add_foreign_key :components, :products
    add_foreign_key :product_members, :products
    add_foreign_key :product_properties, :products
    execute "ALTER TABLE components DROP CONSTRAINT IF EXISTS components_tenant_id_id_key"
    %w[components product_members product_properties].each { |t| remove_column t, :tenant_id }
  end
end
