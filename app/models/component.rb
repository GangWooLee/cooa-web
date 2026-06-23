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
  def versions_asc  = component_versions.sort_by(&:version_number)
  def versions_desc = versions_asc.reverse

  # 비교 진입 기본 쌍 [이전, 최신] — 가치 라벨 없이 단순 버전쌍. 사용자가 선택기로 변경 가능.
  def default_compare_pair
    vs = versions_asc
    vs.size < 2 ? [nil, nil] : [vs[-2], vs[-1]]
  end
end
