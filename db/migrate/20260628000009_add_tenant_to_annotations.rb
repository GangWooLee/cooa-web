require Rails.root.join("lib/tenant_rls").to_s

# Phase 0b M4 — annotations (parent of annotation_comments). Two FKs to component_versions:
# component_version_id (required) and resolved_in_version_id (nullable → MATCH SIMPLE skips when NULL).
class AddTenantToAnnotations < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_tenant_column!("annotations", "(SELECT cv.tenant_id FROM component_versions cv WHERE cv.id = annotations.component_version_id)", parent_unique: true)
    remove_foreign_key :annotations, :component_versions, column: :component_version_id
    remove_foreign_key :annotations, :component_versions, column: :resolved_in_version_id
    composite_fk!("annotations", "component_version_id", "component_versions", name: "annotations_cv_tenant_fkey")
    composite_fk!("annotations", "resolved_in_version_id", "component_versions", name: "annotations_resolved_cv_tenant_fkey")
    enable_tenant_rls!("annotations")
  end

  def down
    disable_tenant_rls!("annotations")
    execute "ALTER TABLE annotations DROP CONSTRAINT IF EXISTS annotations_cv_tenant_fkey"
    execute "ALTER TABLE annotations DROP CONSTRAINT IF EXISTS annotations_resolved_cv_tenant_fkey"
    add_foreign_key :annotations, :component_versions, column: :component_version_id
    add_foreign_key :annotations, :component_versions, column: :resolved_in_version_id
    execute "ALTER TABLE annotations DROP CONSTRAINT IF EXISTS annotations_tenant_id_id_key"
    remove_column :annotations, :tenant_id
  end
end
