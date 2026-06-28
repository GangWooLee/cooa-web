class Component < ApplicationRecord
  include TenantScoped
  belongs_to :product
  has_many :component_versions, -> { order(:version_number) }, dependent: :destroy

  TYPES = {
    "outer_box" => "단상자", "container" => "용기", "insert" => "인서트지",
    "barcode" => "바코드", "etc" => "기타"
  }.freeze
  enum :component_type,
       { outer_box: "outer_box", container: "container", insert: "insert", barcode: "barcode", etc: "etc" },
       prefix: :type

  scope :ordered, -> { order(:position, :id) }

  def type_label = component_type && TYPES[component_type]
  def display_name = name.presence || type_label || "구성요소"
  def current_version = component_versions.detect(&:current) || component_versions.max_by(&:version_number)
  def versions_asc = component_versions.sort_by(&:version_number)
end
