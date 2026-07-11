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

    # 요청-스코프 메모 슬롯: visible_product_ids_or_all(가시 product_id 배열, 또는 nil = tenant-wide 전체)는
    # 요청 내 actor의 순수 함수다(policy_scope에 넘긴 relation과 무관 — id 집합은 오직 grant에서 나옴). Pundit이
    # pundit_user(이 컨텍스트)를 재사용하므로 policy_scope A/B/C·visible_product_id_set(D)가 이 한 슬롯을 공유해
    # 계산이 요청당 1회로 접힌다. R7-safe(원시 id 배열/nil만 캐시). 무효화: 요청 내 grant 불변이 전제(등급
    # 부여/회수는 PRG 리다이렉트라 다음 요청에서 새 컨텍스트로 재계산 — stale 없음). nil도 캐시되게 defined? 가드.
    def visible_product_ids_or_all
      return @visible_product_ids_or_all if defined?(@visible_product_ids_or_all)

      @visible_product_ids_or_all = yield
    end
  end
end
