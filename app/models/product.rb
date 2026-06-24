class Product < ApplicationRecord
  # 자기참조 트리(노션형) — 루트=상위 개념, 자식=변형(국가·용량 등)
  belongs_to :parent, class_name: "Product", optional: true
  belongs_to :owner, class_name: "User", optional: true
  has_many :children, -> { order(:position, :id) }, class_name: "Product",
           foreign_key: :parent_id, dependent: :destroy
  has_many :components, -> { order(:position, :id) }, dependent: :destroy
  has_many :product_members, dependent: :destroy
  has_many :members, through: :product_members, source: :user
  has_many :product_properties, -> { order(:position, :id) }, dependent: :destroy

  scope :roots, -> { where(parent_id: nil).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  normalizes :name, with: ->(v) { v.to_s.strip }
  # 국가 자유입력 — 알려진 라벨/코드는 코드로 정규화(screening fact 매칭 보존), 그 외엔 원문 유지
  normalizes :country, with: ->(v) { ApplicationRecord.normalize_country(v) }
  validates :name, presence: true
  validates :code, uniqueness: { allow_blank: true }
  validate :parent_not_self_or_descendant

  def country_label = ApplicationRecord.country_label(country)
  def member_for(role) = product_members.find_by(role: role)&.user

  # 전체 경로(루트 › … › self) — 드로어 "경로" 표시용
  def path_label = self_and_ancestors.map(&:name).join(" › ")

  # 폴더/항목은 kind로 구분(구조 무관) — 빈 폴더도 폴더로 동작
  def folder? = kind == "folder"
  def leaf?   = !folder?

  # 자기 + 모든 하위 id (이동 시 순환 방지용) — 인-루비 BFS
  def self_and_descendant_ids
    ids = [ id ]
    frontier = children.to_a
    until frontier.empty?
      n = frontier.shift
      ids << n.id
      frontier.concat(n.children.to_a)
    end
    ids.compact
  end

  # 이동/생성 시 상위 후보: 폴더만(트리 순서·depth 포함), 자기·하위 제외.
  # 반환: [[folder, depth], …] — tree_preorder 한 번으로 depth 확보(폼 N+1 회피).
  def self.parent_options_for(node)
    exclude = node&.persisted? ? node.self_and_descendant_ids : []
    tree_preorder.filter_map { |n, d| [ n, d ] if n.folder? && !exclude.include?(n.id) }
  end

  # 조상 경로(루트→…→self) — 브레드크럼/하이라이트용
  def self_and_ancestors
    chain = []
    node = self
    while node
      chain.unshift(node)
      node = node.parent
    end
    chain
  end

  def ancestors = self_and_ancestors[0...-1]
  def depth = ancestors.size

  # 트리 사전순(pre-order) 평탄화 → [[node, depth], …] (대시보드 트리 행용)
  def self.tree_preorder(nodes = roots.includes(:children), level = 0, acc = [])
    nodes.each do |n|
      acc << [ n, level ]
      tree_preorder(n.children, level + 1, acc)
    end
    acc
  end

  private

  def parent_not_self_or_descendant
    return if parent_id.blank?
    if persisted? && self_and_descendant_ids.include?(parent_id)
      errors.add(:parent_id, "자기 자신이나 하위 폴더로 옮길 수 없습니다")
    elsif parent && !parent.folder?
      errors.add(:parent_id, "폴더만 상위가 될 수 있습니다")
    end
  end
end
