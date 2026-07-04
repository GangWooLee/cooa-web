# 조직 멤버 로스터 + pending 초대 목록. 2단 인가(Stage 4 T3): tenant-wide list_tenant_accounts 보유자는
# 전체 로스터(무회귀), scoped brand_admin은 자기 브랜드 서브트리 로스터만(tenant-wide 계정 미표시). 읽기=
# list_tenant_accounts / scoped=자기 브랜드 manage_members, 초대·grant 관리=manage_members(뷰 게이트).
# RLS가 테넌트 스코프를 보장 — 쿼리에 tenant_id 명시 불필요.
class MembersController < ApplicationController
  include MemberAdministration

  def index
    scope = authorize_member_read!(:list_tenant_accounts?)
    scope.is_a?(Array) ? load_scoped_roster(scope) : load_full_roster
  end

  private

  # tenant-wide(:all) 또는 list_tenant_accounts 읽기권자(nil이지만 조직 verb 통과 — 예: lee). 현행 무회귀.
  def load_full_roster
    # scope_product/scope_component 프리로드 = 로스터의 "role@제품" 배지 N+1 회피(R5).
    @accounts    = Account.includes(:user, role_assignments: [ :scope_product, :scope_component ]).order(:created_at)
    @invitations = Invitation.pending.order(created_at: :desc)
    @can_manage  = policy(current_organization).manage_members?
    # 스코프 초대·직접 grant 폼의 제품 select(트리 라벨). manage_members는 tenant-wide 역할이라 RLS 스코프
    # 전 제품이 곧 가시 집합. tree_preorder가 flat 1회 로드 + parent_id 그룹핑 preorder라 depth 무관·쿼리 1건.
    @scope_products = @can_manage ? Product.tree_preorder : []
    @can_issue_tenant_wide = true # tenant-wide admin은 "전체 조직" 초대 발급 가능
  end

  # scoped brand_admin: 자기 브랜드 서브트리에 스코프 grant를 가진 계정만(tenant-wide 계정은 미표시 —
  # 그들은 tenant-wide admin 소관). external 협력자는 부여된 모든 브랜드의 admin에 가시(체인 grant 기준).
  def load_scoped_roster(admin_products)
    admin_product_ids = Product.subtree_ids(admin_products.map(&:id))
    @accounts = Account.includes(:user, role_assignments: [ :scope_product, :scope_component ])
                       .where(id: Authz::AdminScope.scoped_member_account_ids(admin_product_ids)).order(:created_at)
    @invitations = Invitation.pending.where(scope_product_id: admin_product_ids).order(created_at: :desc)
    @can_manage  = true
    @scope_products = Product.tree_preorder(Product.where(id: admin_product_ids))
    @can_issue_tenant_wide = false # scoped admin은 tenant-wide(스코프 없는) 발급 불가 — 서버측 강제(아래 컨트롤러)
  end
end
