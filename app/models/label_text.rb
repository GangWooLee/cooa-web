class LabelText < ApplicationRecord
  include TenantScoped
  belongs_to :component_version
  enum :text_type,
       { label: "label", ad: "ad", ingredient_list: "ingredient_list", other: "other" },
       default: "label"
end
