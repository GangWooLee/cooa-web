module Authz
  # Resolves any tenant-scoped record to its owning Product (the unit role grants attach to) and to the
  # scope ids a role_assignment matches on (Stage 2 D2). Single source so resolver + policies agree.
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

    # The product a product-scoped grant matches on (nil = record has no product context).
    def product_id_for(record) = product_for(record)&.id

    # The component a component-scoped grant matches on. A Component IS its own scope id (the Stage 1 bug:
    # try(:component_id) returned nil for a Component, so a component grant never matched the component
    # itself). A ComponentVersion carries component_id; deeper records have no direct component_id and are
    # covered through their product instead (product_id_for).
    def component_id_for(record) = record.is_a?(Component) ? record.id : record.try(:component_id)

    # WIRED (Stage 2 D2): AssignmentResolver#scoped_roles_for consumes these to match product/component
    # role_assignments. Kept as [product_id, component_id] (compact) for callers that want the chain.
    def scope_chain_ids(record) = [ product_id_for(record), component_id_for(record) ].compact
  end
end
