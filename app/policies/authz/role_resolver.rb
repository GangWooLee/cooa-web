module Authz
  # The ONLY swap surface between Phase 1 (demo User/ProductMember identity) and Phase 2
  # (Account + role_assignment). Policies never touch this — they ask AccessContext#roles_on,
  # which delegates here. Both resolvers return ADR role_key strings, so app/policies is unchanged
  # when the source swaps.
  module RoleResolver
    def self.for(actor)
      case actor
      when Account then AssignmentResolver.new(actor)   # Phase 2
      else DemoResolver.new(actor)                       # Phase 1 (User) / nil
      end
    end

    # Phase 1: derive ADR roles from the demo's User.role enum + product ownership.
    # NOTE: a DEMO calibration — the single fixed operator (designer 김쿠아) is granted brand_admin so
    # the one-user demo can exercise admin flows (member management). Phase 2 replaces this entirely
    # with per-account role_assignment. Deny/SoD tests inject roles directly, independent of this map.
    class DemoResolver
      USER_ROLE_TO_ADR = {
        "designer" => %w[contributor assignee brand_admin],
        "pm" => %w[contributor brand_admin],
        "ra" => %w[ra_reviewer approver],
        "scm" => %w[contributor]
      }.freeze

      def initialize(user) = @user = user

      def roles_on(record)
        return [] unless @user

        roles = USER_ROLE_TO_ADR.fetch(@user.role, %w[viewer]).dup
        product = ResourceScope.product_for(record)
        roles << "owner" if product && product.owner_id == @user.id
        roles.uniq
      end
    end

    # Phase 2, record-DEPENDENT (Stage 2 D2): a record's roles = the actor's tenant-wide grants (apply
    # everywhere) ∪ the grants scoped to THAT record's product/component. Typed FK columns
    # (scope_product_id/scope_component_id) now reconcile with the bigint domain ids.
    class AssignmentResolver
      def initialize(account) = @account = account

      def roles_on(record)
        return [] unless @account

        tenant_wide_roles | scoped_roles_for(record)
      end

      private

      # Record-INDEPENDENT, so memoize per-actor (safe to share across records — a tenant-wide grant applies
      # everywhere). AccessContext caches roles_on by [class, id]; this guards the tenant-wide half against
      # re-querying across N records in a list view (P4 ①b). Request-lived (resolver built per request).
      def tenant_wide_roles
        @tenant_wide_roles ||= RoleAssignment.active.where(account_id: @account.id).tenant_wide.distinct.pluck(:role_key)
      end

      # Record-DEPENDENT, but a pure function of the record's (product_id, component_id) scope key — so
      # memoize by THAT key, never by record. This dedups distinct records sharing a product (a list of
      # annotations under one version = 1 query, not N — the AccessContext [class,id] cache can't dedup
      # those since each record has a distinct key) WITHOUT leaking: different products/components ⇒
      # different keys ⇒ separate queries.
      def scoped_roles_for(record)
        product = Authz::ResourceScope.product_for(record)
        pid = product&.id
        cid = Authz::ResourceScope.component_id_for(record)
        return [] if pid.nil? && cid.nil?

        (@scoped_cache ||= {})[[ pid, cid ]] ||= query_scoped_roles(product, pid, cid)
      end

      # PRODUCT grant covers its whole SUBTREE — coherent with ProductPolicy::Scope (Stage 2 D3: a folder
      # grant surfaces descendant rows, so the resolver must authorize them too, or drill-in fails closed).
      # A record is reached by a grant on its product OR any ANCESTOR (record ∈ subtree(P) ⟺ P ∈ self+ancestors);
      # the in-memory ancestor chain costs 0 queries when :parent is loaded (tree render / product show eager-
      # load it), a bounded walk otherwise. COMPONENT grant matches its EXACT component + versions (via
      # scope_component_id: cid) — no bleed to siblings. PLUS (adversarial-review): the component's OWNING
      # PRODUCT record must be OPENABLE, because ProductPolicy::Scope surfaces it (visible_product_ids maps a
      # component grant to its product) — else the row shows in the tree but drill-in fails closed. So at the
      # product-level key ([pid, nil], i.e. cid nil) a grant on ANY of that product's components also matches.
      # This is a PURE function of the memo key [pid, cid]: it fires only when cid is nil AND is scoped to THIS
      # product's components (Component.where(product_id: pid)) — so a sibling component ([pid, cid≠nil]) is
      # untouched (no bleed) and another product ([other_pid, …]) never leaks. Semantics fully captured in the
      # key ⇒ the scoped_cache memo is safe.
      def query_scoped_roles(product, pid, cid)
        base = RoleAssignment.active.where(account_id: @account.id)
        conds = []
        if pid
          ancestors = product&.self_and_ancestors
          product_ids = ancestors ? ancestors.map(&:id) : [ pid ]
          conds << base.where(scope_product_id: product_ids)
          conds << base.where(scope_component_id: Component.where(product_id: pid).select(:id)) if cid.nil?
          # WORKSPACE grant: 이 레코드의 brand_root가 속한 작업실(작업실 grant는 그 작업실의 모든 루트 서브트리에
          # 적용 → 이 레코드도 포함). ws_id는 pid의 brand_root.workspace_id로 pid의 순수 함수 → [pid,cid] 메모 안전.
          ws_id = ancestors ? ancestors.first.workspace_id : Product.where(id: pid).pick(:workspace_id)
          conds << base.where(scope_workspace_id: ws_id) if ws_id
        end
        conds << base.where(scope_component_id: cid) if cid
        conds.reduce(:or).distinct.pluck(:role_key)
      end
    end
  end
end
