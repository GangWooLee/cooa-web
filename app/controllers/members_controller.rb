# 조직 멤버 로스터 + pending 초대 목록. 읽기=list_tenant_accounts, 초대 관리=manage_members(뷰 게이트).
# RLS가 테넌트 스코프를 보장 — 쿼리에 tenant_id 명시 불필요.
class MembersController < ApplicationController
  def index
    authorize current_organization, :list_tenant_accounts?
    # scope_product/scope_component 프리로드 = 로스터의 "role@제품" 배지 N+1 회피(R5).
    @accounts    = Account.includes(:user, role_assignments: [ :scope_product, :scope_component ]).order(:created_at)
    @invitations = Invitation.pending.order(created_at: :desc)
    @can_manage  = policy(current_organization).manage_members?
    # 스코프 초대·직접 grant 폼의 제품 select(트리 라벨). manage_members는 tenant-wide 역할이라 RLS 스코프
    # 전 제품이 곧 가시 집합.
    @scope_products = @can_manage ? product_scope_tree : []
  end

  private

  def current_organization = Organization.find(Current.tenant_id)

  # [[node, depth], …] 프리오더 트리. 전 제품을 1쿼리로 로드 → parent_id로 in-memory 그룹핑 후 walk.
  # Product.tree_preorder(association walk)은 기본 인자가 1레벨만 프리로드해 하위에서 N+1을 내므로(R5)
  # select 옵션 생성엔 이 in-memory 빌드를 쓴다(depth 무관·쿼리 1건).
  def product_scope_tree
    by_parent = Product.all.to_a.group_by(&:parent_id)
    preorder_products(by_parent, nil, 0, [])
  end

  def preorder_products(by_parent, parent_id, depth, acc)
    (by_parent[parent_id] || []).sort_by { |p| [ p.position || 0, p.id ] }.each do |node|
      acc << [ node, depth ]
      preorder_products(by_parent, node.id, depth + 1, acc)
    end
    acc
  end
end
