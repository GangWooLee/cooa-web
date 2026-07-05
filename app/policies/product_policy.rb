# Inherits all verb predicates from ApplicationPolicy (ADR-002 §6 via matrix). Adds a record-aware
# Scope (Stage 2 D3): policy_scope(Product) is the set of the tenant's products a scope-limited account
# may see. A tenant-wide account (or the demo User path) sees everything — no regression.
class ProductPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      ids = visible_ids_or_all
      return scope if ids.nil?                        # tenant-wide / demo User → everything (no-op)

      ids.empty? ? scope.none : scope.where(id: ids)  # no grant at all → none (fail-closed)
    end

    # The tenant's product ids this actor may see, or nil = "all products visible" (tenant-wide / demo User).
    # SINGLE SOURCE OF VISIBILITY, shared by resolve (row scoping) AND visibility-aware ancestor rendering
    # (ApplicationController#visible_product_id_set → breadcrumb/data-node-path clip) so the two never drift.
    def self.visible_ids_or_all(context) = new(context, Product.all).visible_ids_or_all

    def visible_ids_or_all
      actor = context.actor
      return nil unless actor.is_a?(Account)     # demo/User path (DemoResolver) → all (unchanged)

      grants = RoleAssignment.active.where(account_id: actor.id)
      return nil if grants.tenant_wide.exists?   # any tenant-wide grant → sees everything (no-op)

      visible_product_ids(grants)                # [] → fail-closed (no grant); else the visible id set
    end

    private

    # Granted products expand to self + all descendants (a product grant covers the subtree — the resolver
    # authorizes the SAME subtree via ancestor match, so every surfaced product row is openable); granted
    # components contribute their owning product. One (id, parent_id) load of the tenant's products drives
    # an in-memory descendant walk — no per-node self_and_ancestors N+1.
    def visible_product_ids(grants)
      seed = grants.where.not(scope_product_id: nil).pluck(:scope_product_id)
      comp_ids = grants.where.not(scope_component_id: nil).pluck(:scope_component_id)
      seed |= Component.where(id: comp_ids).pluck(:product_id) if comp_ids.any?
      # WORKSPACE grant → 그 작업실의 모든 루트(그 후 서브트리로 확장). 루트만 workspace_id를 실으므로 루트 조회로 충분.
      ws_ids = grants.where.not(scope_workspace_id: nil).pluck(:scope_workspace_id)
      seed |= Product.roots.where(workspace_id: ws_ids).pluck(:id) if ws_ids.any?
      return [] if seed.empty?

      expand_descendants(seed.uniq)
    end

    # A product grant covers self + all descendants. Shared in-memory expansion (Product.subtree_ids):
    # one (id, parent_id) load, no per-node children recursion. Same algorithm the members scoped roster
    # (T3) and the brand page (T4) reuse, so the subtree definition never drifts.
    def expand_descendants(seed) = Product.subtree_ids(seed)
  end
end
