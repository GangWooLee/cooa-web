# Per-request context (ActiveSupport::CurrentAttributes).
class Current < ActiveSupport::CurrentAttributes
  attribute :user                 # demo legacy (fixed auto-login) — removed when Account auth lands (Phase 2)
  attribute :account              # authenticated principal (Phase 2)
  attribute :tenant_id            # SERVER-resolved tenant — never trust a client claim (ADR-002 §7 / ADR-003 §2.1)
  attribute :claims               # verified token claims (Phase 2)
end
