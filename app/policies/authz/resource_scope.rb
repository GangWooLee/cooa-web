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

    # Phase 2 (AssignmentResolver): the scope_ids a role_assignment may target for this record.
    def scope_chain_ids(record)
      [product_for(record)&.id, record.try(:component_id)].compact
    end
  end
end
