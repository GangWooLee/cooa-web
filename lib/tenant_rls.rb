# Shared helpers for Phase 0b domain-table tenant-isolation migrations (ADR-002 §7).
# Same RLS predicate as the foundation tables (NULLIF -> fail-CLOSED). `require`d explicitly
# by each migration to avoid autoload timing surprises during db:migrate.
module TenantRls
  def enable_tenant_rls!(table)
    execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
    execute <<~SQL
      CREATE POLICY tenant_isolation ON #{table}
        USING      (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
    SQL
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO cooa_app"
  end

  def disable_tenant_rls!(table)
    execute "DROP POLICY IF EXISTS tenant_isolation ON #{table}"
    execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
  end

  # The single demo tenant existing rows backfill into (created on demand). Idempotent by name.
  def seed_org_id
    existing = select_value("SELECT id FROM organizations WHERE name = 'COOA Demo' LIMIT 1")
    return existing if existing

    select_value(<<~SQL)
      INSERT INTO organizations (id, name, region, billing_tier, impersonation_opt_out, created_at, updated_at)
      VALUES (gen_random_uuid(), 'COOA Demo', 'JP', 'starter', false, now(), now())
      RETURNING id
    SQL
  end

  # Backfill tenant_id from `value_sql` (a literal-quoted uuid for the root, or a correlated
  # subquery for child tables), then HARD-GUARD that no NULLs remain before NOT NULL is set.
  def backfill_tenant!(table, value_sql)
    execute "UPDATE #{table} SET tenant_id = #{value_sql} WHERE tenant_id IS NULL"
    remaining = select_value("SELECT COUNT(*) FROM #{table} WHERE tenant_id IS NULL").to_i
    raise "#{table}.tenant_id still has #{remaining} NULL row(s) after backfill — aborting" if remaining.positive?
  end

  # add column -> backfill (only if rows) -> NOT NULL -> index -> optional UNIQUE(tenant_id,id) for parents.
  def add_tenant_column!(table, backfill_value_sql, parent_unique: false)
    add_column table, :tenant_id, :uuid
    if select_value("SELECT COUNT(*) FROM #{table} WHERE tenant_id IS NULL").to_i.positive?
      backfill_tenant!(table, backfill_value_sql)
    end
    change_column_null table, :tenant_id, false
    add_index table, :tenant_id
    execute "ALTER TABLE #{table} ADD CONSTRAINT #{table}_tenant_id_id_key UNIQUE (tenant_id, id)" if parent_unique
  end

  # Same-tenant composite FK. Nullable fk_col is fine: PG MATCH SIMPLE skips the check when fk_col IS NULL.
  def composite_fk!(table, fk_col, parent_table, name:)
    execute <<~SQL
      ALTER TABLE #{table}
        ADD CONSTRAINT #{name} FOREIGN KEY (tenant_id, #{fk_col}) REFERENCES #{parent_table} (tenant_id, id)
    SQL
  end
end
