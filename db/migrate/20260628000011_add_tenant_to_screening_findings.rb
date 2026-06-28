require Rails.root.join("lib/tenant_rls").to_s

# Phase 0b M6 — screening_findings (leaf). tenant_id derived from screening_run.
class AddTenantToScreeningFindings < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_tenant_column!("screening_findings", "(SELECT sr.tenant_id FROM screening_runs sr WHERE sr.id = screening_findings.screening_run_id)")
    remove_foreign_key :screening_findings, :screening_runs
    composite_fk!("screening_findings", "screening_run_id", "screening_runs", name: "screening_findings_run_tenant_fkey")
    enable_tenant_rls!("screening_findings")
  end

  def down
    disable_tenant_rls!("screening_findings")
    execute "ALTER TABLE screening_findings DROP CONSTRAINT IF EXISTS screening_findings_run_tenant_fkey"
    add_foreign_key :screening_findings, :screening_runs
    remove_column :screening_findings, :tenant_id
  end
end
