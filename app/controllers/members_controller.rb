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
    # 전 제품이 곧 가시 집합. tree_preorder가 flat 1회 로드 + parent_id 그룹핑 preorder라 depth 무관·쿼리 1건
    # (구 로컬 in-memory 빌드를 역-통합 — H2).
    @scope_products = @can_manage ? Product.tree_preorder : []
  end

  private

  def current_organization = Organization.find(Current.tenant_id)
end
