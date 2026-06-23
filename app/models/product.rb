class Product < ApplicationRecord
  # 자기참조 트리(노션형) — 루트=상위 개념, 자식=변형(국가·용량 등)
  belongs_to :parent, class_name: "Product", optional: true
  belongs_to :owner, class_name: "User", optional: true
  has_many :children, -> { order(:position, :id) }, class_name: "Product",
           foreign_key: :parent_id, dependent: :destroy
  has_many :components, -> { order(:position, :id) }, dependent: :destroy
  has_many :product_members, dependent: :destroy
  has_many :members, through: :product_members, source: :user

  scope :roots, -> { where(parent_id: nil).order(:position, :id) }
  scope :ordered, -> { order(:position, :id) }

  def country_label = ApplicationRecord.country_label(country)
  def member_for(role) = product_members.find_by(role: role)&.user

  def leaf?   = children.empty?
  def folder? = children.any?

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
      acc << [n, level]
      tree_preorder(n.children, level + 1, acc)
    end
    acc
  end
end
