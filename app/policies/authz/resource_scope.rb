module Authz
  # Resolves any tenant-scoped record to its owning Product (the unit role grants attach to) and to
  # the scope-id chain (Phase 2 role_assignment matching). Single source so both resolvers agree.
  module ResourceScope
    module_function

    def product_for(record)
      case record
      when Product then record
      when Component then record.product
      when ComponentVersion then record.component&.product
      when Annotation then record.component_version&.component&.product
      when AnnotationComment then record.annotation&.component_version&.component&.product
      when ScreeningRun then record.component_version&.component&.product
      when ScreeningFinding then record.screening_run&.component_version&.component&.product
      when Ingredient, LabelText then record.component_version&.component&.product
      when ProductMember, ProductProperty then record.product
      end
    end

    # Phase 2b — UNWIRED (no caller yet). Holds the scope_id↔domain-id matching for product/component-scoped
    # role_assignments; 2a uses tenant-wide grants only (scope_id IS NULL). See freeze spec §3 (P3 M1).
    def scope_chain_ids(record)
      [ product_for(record)&.id, record.try(:component_id) ].compact
    end
  end
end
