# Row-Level Security on the foundation tables (ADR-002 §7.1).
# - ENABLE + FORCE: RLS applies to everyone incl. the table owner (only a SUPERUSER or BYPASSRLS role bypasses).
# - Policy is role-agnostic (applies to all non-bypassing roles); cooa_app gets DML via GRANT.
# - NULLIF(current_setting('app.current_tenant_id', true), '') → unset context yields NULL → 0 rows (fail-CLOSED),
#   never the whole table. `, true` = missing_ok so an unset GUC doesn't raise.
class EnableRlsOnFoundation < ActiveRecord::Migration[8.1]
  # table => tenant-key column (organizations' own id IS the tenant)
  TENANT_TABLES = { "organizations" => "id", "accounts" => "tenant_id", "role_assignments" => "tenant_id" }.freeze

  def up
    TENANT_TABLES.each do |table, col|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;"
      execute <<~SQL
        CREATE POLICY tenant_isolation ON #{table}
          USING (#{col} = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid)
          WITH CHECK (#{col} = NULLIF(current_setting('app.current_tenant_id', true), '')::uuid);
      SQL
      execute "GRANT SELECT, INSERT, UPDATE, DELETE ON #{table} TO cooa_app;"
    end
    execute "GRANT USAGE ON SCHEMA public TO cooa_app;"
  end

  def down
    TENANT_TABLES.each_key do |table|
      execute "DROP POLICY IF EXISTS tenant_isolation ON #{table};"
      execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY;"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;"
    end
  end
end
