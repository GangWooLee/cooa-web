module Authz
  # The Pundit "user" object. Wraps the authenticated actor (Phase 1 = Current.user; Phase 2 =
  # Current.account) and exposes only what policies need: roles_on(record) and actor_id (for SoD).
  # roles_on is memoized per (class,id) for the request to avoid N+1 in policy_scope / repeated authorize.
  class AccessContext
    attr_reader :actor

    def initialize(actor:, resolver: nil)
      @actor = actor
      @resolver = resolver || RoleResolver.for(actor)
      @cache = {}
    end

    # SoD identity must live in the DOMAIN FK space (User bigint), not the Account uuid. An Account
    # bridges via domain_user_id (its linked user_id); a bare User actor uses its own id. Otherwise
    # requested_by_id(bigint) != actor_id(uuid) is always true → self-approval fail-open (ADR-003 gate).
    def actor_id = actor.respond_to?(:domain_user_id) ? actor.domain_user_id : actor&.id

    def roles_on(record)
      key = [ record.class.name, record.try(:id) ]
      @cache[key] ||= @resolver.roles_on(record)
    end
  end
end
