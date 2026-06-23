class Component < ApplicationRecord
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

  def type_label = TYPES[component_type]
  def current_version = component_versions.detect(&:current) || component_versions.max_by(&:version_number)
  def versions_desc = component_versions.sort_by(&:version_number).reverse

  # 비교쌍 [from(현 위치/이전), to(비교 대상/최신)] — 비교 화면 진입용
  def compare_pair
    return [nil, nil] if component_versions.size < 2
    cur   = current_version
    newer = component_versions.select { |v| v.version_number > cur.version_number }.min_by(&:version_number)
    older = component_versions.select { |v| v.version_number < cur.version_number }.max_by(&:version_number)
    newer ? [cur, newer] : [older, cur]
  end
end
