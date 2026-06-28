require Rails.root.join("lib/tenant_rls").to_s

# Phase 0b M3 — component_versions (parent of annotations/ingredients/label_texts/screening_runs)
# + its direct children ingredients/label_texts/screening_runs. tenant_id derived from component/version.
class AddTenantToComponentVersionsAndKin < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_tenant_column!("component_versions", "(SELECT c.tenant_id FROM components c WHERE c.id = component_versions.component_id)", parent_unique: true)
    remove_foreign_key :component_versions, :components
    composite_fk!("component_versions", "component_id", "components", name: "component_versions_component_tenant_fkey")
    enable_tenant_rls!("component_versions")

    add_tenant_column!("ingredients", "(SELECT cv.tenant_id FROM component_versions cv WHERE cv.id = ingredients.component_version_id)")
    remove_foreign_key :ingredients, :component_versions
    composite_fk!("ingredients", "component_version_id", "component_versions", name: "ingredients_cv_tenant_fkey")
    enable_tenant_rls!("ingredients")

    add_tenant_column!("label_texts", "(SELECT cv.tenant_id FROM component_versions cv WHERE cv.id = label_texts.component_version_id)")
    remove_foreign_key :label_texts, :component_versions
    composite_fk!("label_texts", "component_version_id", "component_versions", name: "label_texts_cv_tenant_fkey")
    enable_tenant_rls!("label_texts")

    add_tenant_column!("screening_runs", "(SELECT cv.tenant_id FROM component_versions cv WHERE cv.id = screening_runs.component_version_id)", parent_unique: true)
    remove_foreign_key :screening_runs, :component_versions
    composite_fk!("screening_runs", "component_version_id", "component_versions", name: "screening_runs_cv_tenant_fkey")
    enable_tenant_rls!("screening_runs")
  end

  def down
    %w[component_versions ingredients label_texts screening_runs].each { |t| disable_tenant_rls!(t) }
    execute "ALTER TABLE component_versions DROP CONSTRAINT IF EXISTS component_versions_component_tenant_fkey"
    execute "ALTER TABLE ingredients DROP CONSTRAINT IF EXISTS ingredients_cv_tenant_fkey"
    execute "ALTER TABLE label_texts DROP CONSTRAINT IF EXISTS label_texts_cv_tenant_fkey"
    execute "ALTER TABLE screening_runs DROP CONSTRAINT IF EXISTS screening_runs_cv_tenant_fkey"
    add_foreign_key :component_versions, :components
    add_foreign_key :ingredients, :component_versions
    add_foreign_key :label_texts, :component_versions
    add_foreign_key :screening_runs, :component_versions
    execute "ALTER TABLE component_versions DROP CONSTRAINT IF EXISTS component_versions_tenant_id_id_key"
    execute "ALTER TABLE screening_runs DROP CONSTRAINT IF EXISTS screening_runs_tenant_id_id_key"
    %w[component_versions ingredients label_texts screening_runs].each { |t| remove_column t, :tenant_id }
  end
end
