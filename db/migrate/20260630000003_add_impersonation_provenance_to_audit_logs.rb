# P6 #2 — audit provenance for break-glass / owner-recovery impersonation. Added now (forward
# infrastructure) so the 2b impersonation flow is no-rework. nil for every normal row; the audit hash
# OMITS them when nil (AuditLog#canonical_body), so existing chains stay byte-identical and audit:verify
# is unaffected. audit_logs already carries RLS + the cooa_app SELECT/INSERT grant → columns inherit both.
class AddImpersonationProvenanceToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :on_behalf_of_account_id, :uuid    # the impersonator (cooa_staff) acting on behalf
    add_column :audit_logs, :impersonation_session_id, :bigint # FK → impersonation_sessions (the recovery flow)
    add_column :audit_logs, :impersonation_context, :jsonb     # { category, reason, approver, … } snapshot
  end
end
