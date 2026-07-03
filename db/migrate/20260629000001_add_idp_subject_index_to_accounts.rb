# Phase 2b-1 — one Account per (tenant, idp_subject). Partial (WHERE idp_subject IS NOT NULL) so the
# seed sentinel "local|<name>" coexists and OIDC JIT cannot bind one subject to two accounts. The
# idp_subject column already exists (Phase 0a accounts). Run as the owner (COOA_DB_USER).
class AddIdpSubjectIndexToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_index :accounts, [ :tenant_id, :idp_subject ], unique: true,
              where: "idp_subject IS NOT NULL",
              name: "index_accounts_on_tenant_id_and_idp_subject"
  end
end
