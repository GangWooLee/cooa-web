# Mixed into every tenant-scoped domain model (Phase 0b). On create, stamps tenant_id from the
# server-resolved Current.tenant_id (ADR-002 §7) — never a client-supplied value. RLS WITH CHECK +
# the composite FKs are the hard backstop; this is the ergonomic default so app/seed/test code
# need not pass tenant_id explicitly.
module TenantScoped
  extend ActiveSupport::Concern

  included do
    before_validation :assign_current_tenant, on: :create
  end

  private

  def assign_current_tenant
    # ||= keeps an explicit value (seed/test). A nil Current.tenant_id assigns nil → RLS WITH CHECK + the
    # NOT NULL column fail-CLOSED (the row is rejected), never a cross-tenant leak. Intentional — no raise
    # (would break factories that set the RLS context out-of-band). (P3 L1)
    self.tenant_id ||= Current.tenant_id
  end
end
