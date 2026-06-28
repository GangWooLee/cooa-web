module Authz
  # role_key → permitted verbs, transcribed verbatim from ADR-002 §6 (자원 × 액션 매트릭스).
  # external_collaborator entries are "scoped" in the ADR — RLS + resource scoping enforce the
  # scope; the verb set here is the ceiling. cooa_staff has NO standing grants (break-glass only).
  module PermissionMatrix
    MATRIX = {
      "viewer" => %w[
        view_tenant view_product view_component_version view_screening_findings
      ].freeze,
      "contributor" => %w[
        view_tenant view_product view_component_version upload_version
        leave_feedback run_screening view_screening_findings
        share_findings route_for_review request_modification submit_for_approval
      ].freeze,
      "assignee" => %w[
        view_tenant list_tenant_accounts view_product view_component_version manage_product upload_version
        leave_feedback resolve_feedback run_screening view_screening_findings
        share_findings route_for_review request_modification submit_for_approval export_signed_report
      ].freeze,
      "ra_reviewer" => %w[
        view_tenant list_tenant_accounts view_product view_component_version
        leave_feedback resolve_feedback run_screening view_screening_findings
        share_findings route_for_review request_modification submit_for_approval export_signed_report
      ].freeze,
      "approver" => %w[
        view_tenant list_tenant_accounts view_product view_component_version
        leave_feedback view_screening_findings share_findings route_for_review request_modification
        approve reject export_signed_report delegate_approval
      ].freeze,
      "brand_admin" => %w[
        view_tenant list_tenant_accounts manage_tenant_settings view_product view_component_version
        manage_product upload_version leave_feedback resolve_feedback run_screening view_screening_findings
        share_findings route_for_review request_modification manage_assignee manage_members
        export_signed_report delegate_approval
      ].freeze,
      "owner" => %w[
        view_tenant list_tenant_accounts manage_tenant_settings view_product view_component_version
        manage_product upload_version leave_feedback resolve_feedback run_screening view_screening_findings
        share_findings route_for_review request_modification manage_assignee manage_members
        submit_for_approval approve reject export_signed_report delegate_approval
      ].freeze,
      "external_collaborator" => %w[
        view_tenant view_product view_component_version upload_version
        leave_feedback view_screening_findings share_findings route_for_review request_modification
      ].freeze,
      "cooa_staff" => [].freeze,
    }.freeze

    def self.allows?(role_key, verb)
      MATRIX.fetch(role_key, []).include?(verb.to_s)
    end
  end
end
