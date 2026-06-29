require Rails.root.join("lib/tenant_rls").to_s

# Phase 3a — append-only, hash-chained audit log (ADR-002 §5.4). Tenant-isolated (RLS); immutable via
# (a) cooa_app SELECT+INSERT-only grant AND (b) a BEFORE UPDATE/DELETE trigger that blocks even the
# owner. Records BOTH allow and deny. Run as the owner (COOA_DB_USER).
class CreateAuditLogs < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    create_table :audit_logs do |t|
      t.uuid     :tenant_id, null: false
      t.string   :region
      t.bigint   :actor_id           # User(bigint) — SoD/requested_by_id space; nil allowed for deny
      t.uuid     :actor_account_id   # Account-era cross-reference
      t.string   :action, null: false
      t.string   :resource_type, null: false
      t.bigint   :resource_id
      t.string   :outcome, null: false # allow | deny
      t.string   :denial_reason
      t.integer  :policy_version, null: false, default: 0
      t.jsonb    :before
      t.jsonb    :after
      t.inet     :source_ip
      t.string   :request_id
      t.string   :user_agent
      t.bigint   :tenant_seq, null: false # per-tenant monotonic (gap detection)
      t.string   :prev_chain_hash
      t.string   :chain_hash, null: false
      t.datetime :ts, null: false, default: -> { "now()" } # model sets it before hashing
    end
    add_index :audit_logs, [:tenant_id, :tenant_seq], unique: true
    add_index :audit_logs, [:tenant_id, :ts]
    add_index :audit_logs, [:tenant_id, :actor_id, :ts]
    add_index :audit_logs, [:tenant_id, :outcome]
    add_index :audit_logs, [:tenant_id, :resource_type, :resource_id, :ts]

    enable_append_only_rls!("audit_logs")

    # Immutability trigger — pg_dump preserves it into structure.sql, so it protects even the owner and
    # a grant-misapplied environment (defense the volatile GRANT cannot give).
    execute <<~SQL
      CREATE FUNCTION audit_logs_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'audit_logs is append-only (% blocked)', TG_OP; END $$;
      CREATE TRIGGER audit_logs_no_mutate BEFORE UPDATE OR DELETE ON audit_logs
        FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS audit_logs_no_mutate ON audit_logs"
    execute "DROP FUNCTION IF EXISTS audit_logs_immutable()"
    drop_table :audit_logs
  end
end
