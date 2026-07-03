require Rails.root.join("lib/tenant_rls").to_s

# Phase 3b — approval workflow aggregate (ADR-002 §5.3). approval_request signs the *reviewed tuple*
# (C1); a single two-eyes approval_step records the Part-11 signature. Tenant-isolated (RLS) + composite
# FKs to parents that already carry UNIQUE(tenant_id, id) (screening_runs from Phase 0b). submitter/
# approver are simple FKs to the global, non-tenant `users` table. Run as the owner (COOA_DB_USER).
class CreateApprovalWorkflowTables < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    create_table :approval_requests do |t|
      t.uuid     :tenant_id, null: false
      t.bigint   :screening_run_id, null: false
      t.bigint   :submitter_id, null: false             # User (bigint) — same space as requested_by_id
      t.string   :market, null: false                   # = screening_run.country
      t.string   :status, null: false, default: "pending" # pending|blocked_no_approver|approved|rejected|cancelled
      # C1 reviewed tuple — captured at submit, immutable, re-validated at approve
      t.string   :reviewed_artifact_digest, null: false
      t.string   :reviewed_content_snapshot_hash, null: false
      t.string   :ruleset_version, null: false
      t.string   :engine_version, null: false
      t.string   :disclaimer_version, null: false
      t.jsonb    :verdict_snapshot, null: false, default: []
      t.datetime :reviewed_at, null: false
      t.integer  :lock_version, null: false, default: 0  # optimistic lock
      t.timestamps
    end
    execute "ALTER TABLE approval_requests ADD CONSTRAINT approval_requests_tenant_id_id_key UNIQUE (tenant_id, id)"
    add_index :approval_requests, [ :tenant_id, :screening_run_id ], unique: true # one request per run
    add_index :approval_requests, [ :tenant_id, :status ]
    composite_fk!(:approval_requests, :screening_run_id, :screening_runs, name: "approval_requests_run_tenant_fkey")
    add_foreign_key :approval_requests, :users, column: :submitter_id
    enable_tenant_rls!("approval_requests")

    create_table :approval_steps do |t|
      t.uuid     :tenant_id, null: false
      t.bigint   :approval_request_id, null: false
      t.bigint   :approver_id, null: false              # User (bigint)
      t.string   :decision, null: false                 # approved | rejected
      t.string   :meaning, null: false, default: "approved" # Part-11 signature meaning
      t.text     :reason
      t.datetime :acted_at, null: false
      t.integer  :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :approval_steps, [ :tenant_id, :approval_request_id ], unique: true # two-eyes single step
    composite_fk!(:approval_steps, :approval_request_id, :approval_requests, name: "approval_steps_request_tenant_fkey")
    add_foreign_key :approval_steps, :users, column: :approver_id
    enable_tenant_rls!("approval_steps")
  end

  def down
    drop_table :approval_steps
    drop_table :approval_requests
  end
end
