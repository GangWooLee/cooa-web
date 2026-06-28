# Server-resolved tenant scoping for Postgres RLS (ADR-002 §7.1).
#
# `with_tenant` wraps a block in a transaction and sets `app.current_tenant_id` via
# set_config(..., true) = SET LOCAL — transaction-scoped, so it auto-clears at commit/rollback
# and can never leak to the next pooled checkout. The RLS policy reads this GUC; an unset value
# (NULLIF -> NULL) yields zero rows (fail-CLOSED), never the whole table.
#
# Phase 0a: used by tests/jobs (pass a connection). Phase 2: ApplicationController#around_action
# resolves the tenant from the authenticated Account and wraps each request the same way.
module TenantContext
  module_function

  def with_tenant(tenant_id, connection: ActiveRecord::Base.connection)
    raise ArgumentError, "tenant_id is required (tenant context must never be unset for scoped work)" if tenant_id.blank?

    connection.transaction do
      connection.execute(
        "SELECT set_config('app.current_tenant_id', #{connection.quote(tenant_id.to_s)}, true)"
      )
      yield
    end
  end
end
