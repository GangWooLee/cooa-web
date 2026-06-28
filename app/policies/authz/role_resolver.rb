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
        "scm" => %w[contributor],
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

    # Phase 2 stub — same interface, reads role_assignment. NOTE: role_assignment.scope_id is uuid
    # while domain ids are bigint; the scope_id↔domain-id reconciliation is Phase 2 work. For now this
    # returns tenant-wide grants (scope_id IS NULL) so the interface is exercised/frozen.
    class AssignmentResolver
      def initialize(account) = @account = account

      def roles_on(_record)
        return [] unless @account

        RoleAssignment.where(account_id: @account.id, scope_id: nil)
                      .select(&:active?).map(&:role_key).uniq
      end
    end
  end
end
