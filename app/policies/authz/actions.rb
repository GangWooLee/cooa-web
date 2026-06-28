module Authz
  # The canonical action vocabulary (ADR-002 §4.3) — defined ONCE, used verbatim by policies,
  # the permission matrix, the UI, and (later) Cerbos YAML. Freezing this is the load-bearing
  # artifact that prevents drift. Authz::Actions.valid? guards against typo'd verbs (silent
  # authorization failure is the worst outcome).
  module Actions
    CORE = %w[
      view_tenant list_tenant_accounts manage_tenant_settings
      view_product view_component_version upload_version manage_product
      leave_feedback resolve_feedback
      run_screening view_screening_findings
      manage_assignee manage_members
      submit_for_approval approve reject
    ].freeze

    SI_LEAN = %w[share_findings route_for_review request_modification export_signed_report].freeze
    DEFERRED = %w[delegate_approval].freeze            # join-rule engine, Phase 3+
    STAFF = %w[impersonate_tenant].freeze              # break-glass only (ADR-003 §5)

    ALL = (CORE + SI_LEAN + DEFERRED + STAFF).freeze

    def self.valid?(verb) = ALL.include?(verb.to_s)
  end
end
