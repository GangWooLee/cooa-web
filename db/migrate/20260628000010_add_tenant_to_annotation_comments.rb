require Rails.root.join("lib/tenant_rls").to_s

# Phase 0b M5 — annotation_comments. FK to annotations + self-ref parent_id (nullable thread reply).
class AddTenantToAnnotationComments < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_tenant_column!("annotation_comments", "(SELECT a.tenant_id FROM annotations a WHERE a.id = annotation_comments.annotation_id)", parent_unique: true)
    remove_foreign_key :annotation_comments, :annotations
    remove_foreign_key :annotation_comments, :annotation_comments, column: :parent_id
    composite_fk!("annotation_comments", "annotation_id", "annotations", name: "annotation_comments_annotation_tenant_fkey")
    composite_fk!("annotation_comments", "parent_id", "annotation_comments", name: "annotation_comments_parent_tenant_fkey")
    enable_tenant_rls!("annotation_comments")
  end

  def down
    disable_tenant_rls!("annotation_comments")
    execute "ALTER TABLE annotation_comments DROP CONSTRAINT IF EXISTS annotation_comments_annotation_tenant_fkey"
    execute "ALTER TABLE annotation_comments DROP CONSTRAINT IF EXISTS annotation_comments_parent_tenant_fkey"
    add_foreign_key :annotation_comments, :annotations
    add_foreign_key :annotation_comments, :annotation_comments, column: :parent_id
    execute "ALTER TABLE annotation_comments DROP CONSTRAINT IF EXISTS annotation_comments_tenant_id_id_key"
    remove_column :annotation_comments, :tenant_id
  end
end
