class Ingredient < ApplicationRecord
  include TenantScoped
  belongs_to :component_version
end
