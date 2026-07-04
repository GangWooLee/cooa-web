# frozen_string_literal: true

# Shared teardown for the two NON-transactional RLS suites (rls_isolation_test + rls_app_connection_test).
# Those suites set use_transactional_tests = false (cross-connection visibility needs COMMITTED rows), so
# there is NO rollback safety net: a teardown that aborts partway LEAKS committed orgs/accounts/products
# into the next run, and a leaked committed row later poisons a global assertion in another suite — the
# structural root of the intermittent flake this module seals.
#
# Guarantees:
#   * SINGLE SOURCE for the cooa_app grant lists (RLS_TABLES / READ_ONLY). They were duplicated verbatim in
#     both suites; a silent drift would misgrant one. Both suites now `include CommittedStateCleanup`, and
#     the bare `RLS_TABLES` / `READ_ONLY` references in their setup resolve here via the ancestor chain.
#   * FK-safe, per-step-isolated cleanup: each delete/destroy runs in its own begin/rescue so ONE failure
#     (e.g. a newly added FK) prints a warning and the REMAINING steps still run — no half-cleanup leak.
#     Idempotent: re-callable, and absent rows are no-ops.
module CommittedStateCleanup
  # cooa_app DML targets (RLS-protected) + read-only refs (global KB / users). structure.sql strips GRANTs
  # (pg_dump -x), so each suite (re)applies them as the owner in setup — this is the one definition.
  RLS_TABLES = "organizations, accounts, role_assignments, products, components, component_versions, " \
               "annotations, annotation_comments, ingredients, label_texts, screening_runs, " \
               "screening_findings, product_members, product_properties".freeze
  READ_ONLY = "users, ingredient_limits, label_requirements, ad_risk_expressions".freeze

  # Delete the committed rows the RLS suites create, org-scoped, in FK-safe order, each step isolated.
  # role_assignments.account_id → accounts and accounts.tenant_id → organizations dictate the order:
  # products → role_assignments → accounts → organizations. (users are global / not org-scoped — the one
  # suite that creates a User destroys it itself, after this returns and its accounts are already gone.)
  def cleanup_committed_rls_state!(org_ids)
    ids = Array(org_ids).compact
    return if ids.empty?

    isolate("products")         { Product.where(tenant_id: ids).delete_all }
    isolate("role_assignments") { RoleAssignment.where(tenant_id: ids).delete_all }
    isolate("accounts")         { Account.where(tenant_id: ids).delete_all }
    ids.each { |oid| isolate("organization #{oid}") { Organization.where(id: oid).destroy_all } }
  end

  private

  # Run one cleanup step; a failure must NOT abort the remaining steps (that is exactly how committed rows
  # leaked). Warn and continue — the next run's setup + this idempotent teardown re-attempt the rest.
  def isolate(label)
    yield
  rescue StandardError => e
    warn "[committed-cleanup] #{label} failed (continuing): #{e.class}: #{e.message}"
  end
end
