# Base Pundit policy (ADR-002 Layer B). The Pundit "user" is an Authz::AccessContext.
# Generic gate: a verb is allowed if ANY role the actor holds on the record permits it (PermissionMatrix).
# A predicate method is defined for every action verb, so controllers call authorize(record, :verb?).
# Resource subclasses only override verbs that need extra predicates (e.g., ScreeningRunPolicy SoD).
class ApplicationPolicy
  attr_reader :context, :record

  def initialize(context, record)
    @context = context
    @record = record
  end

  # roles_on(record) ∩ matrix(verb)
  def can?(verb)
    raise ArgumentError, "unknown action verb: #{verb.inspect}" unless Authz::Actions.valid?(verb)

    context.roles_on(record).any? { |role_key| Authz::PermissionMatrix.allows?(role_key, verb) }
  end

  # view_product?, manage_product?, run_screening?, approve?, … one per ADR §4.3 verb.
  Authz::Actions::ALL.each do |verb|
    define_method(:"#{verb}?") { can?(verb) }
  end

  # policy_scope: pass-through by default. RLS already restricts rows to the current tenant; this
  # layer would add role-based visibility WITHIN the tenant. Do NOT re-add a tenant WHERE here
  # (that would mask an RLS misconfiguration). Subclasses override resolve for role subsetting.
  class Scope
    attr_reader :context, :scope

    def initialize(context, scope)
      @context = context
      @scope = scope
    end

    def resolve = scope
  end
end
