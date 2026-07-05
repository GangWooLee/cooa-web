# 조직 멤버 로스터 + pending 초대 목록. 2단 인가(Stage 4 T3): tenant-wide list_tenant_accounts 보유자는
# 전체 로스터(무회귀), scoped brand_admin은 자기 작업실 서브트리 로스터만(tenant-wide 계정 미표시). 읽기=
# list_tenant_accounts / scoped=자기 작업실 manage_members, 초대·grant 관리=manage_members(뷰 게이트).
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
    # scope_workspace/scope_product/scope_component 프리로드 = 로스터의 "소속 작업실" 배지 N+1 회피(R5).
    @accounts    = Account.includes(:user, role_assignments: [ :scope_workspace, :scope_product, :scope_component ]).order(:created_at)
    @invitations = Invitation.pending.order(created_at: :desc)
    @can_manage  = policy(current_organization).manage_members?
    # 배지 "소속 작업실" 해석(읽기전용 링크)은 읽기 전용 열람자(예: approver lee)에게도 필요 → 항상 구성(전 제품 로드 1건).
    build_workspace_context(Product.all)
    @can_issue_tenant_wide = true # tenant-wide admin은 "전사 초대"(모든 작업실 접근) 발급 가능
  end

  # scoped brand_admin: 자기 작업실 서브트리에 스코프 grant를 가진 계정만(tenant-wide 계정은 미표시 —
  # 그들은 tenant-wide admin 소관). external 협력자는 부여된 모든 작업실의 admin에 가시(스코프 grant 기준).
  def load_scoped_roster(admin_products)
    admin_product_ids = Product.subtree_ids(admin_products.map(&:id))
    @accounts = Account.includes(:user, role_assignments: [ :scope_workspace, :scope_product, :scope_component ])
                       .where(id: Authz::AdminScope.scoped_member_account_ids(admin_product_ids)).order(:created_at)
    @invitations = pending_invitations_for(admin_product_ids)
    @can_manage  = true
    build_workspace_context(Product.where(id: admin_product_ids)) # 자기 작업실 서브트리만
    @can_issue_tenant_wide = false # scoped admin은 tenant-wide(스코프 없는) 발급 불가 — 서버측 강제(아래 컨트롤러)
  end

  # 로스터 "소속 작업실" 배지(읽기전용·링크) 해석용 맵. 주어진 제품 집합을 1회 로드해 in-memory로 각 제품의
  # 작업실을 계산한다(조상 walk N+1 0건 — 로스터 N+1 게이트가 커버). D5에서 "작업실에 추가" 폼을 은퇴시켰으므로
  # @workspaces(select 후보)는 더 이상 만들지 않는다.
  #   @workspace_id_of  = 제품 id → 그 제품의 작업실 id(루트 walk) → 배지 "role · 작업실명/링크" 해석.
  #   @workspace_by_id  = 작업실 id → Workspace(배지 이름·링크 lookup).
  def build_workspace_context(product_scope)
    products = product_scope.to_a
    by_id = products.index_by(&:id)
    @workspace_id_of = products.each_with_object({}) do |p, h|
      cur = p
      cur = by_id[cur.parent_id] while cur.parent_id && by_id.key?(cur.parent_id)
      h[p.id] = cur.workspace_id
    end
    @workspace_by_id = Workspace.where(id: @workspace_id_of.values.compact.uniq).ordered.index_by(&:id)
  end

  # 스코프 admin의 대기 초대 = 관할 작업실-스코프 초대 ∪ 관할 서브트리 제품/구성요소-스코프 초대.
  def pending_invitations_for(product_ids)
    ws_ids = Product.where(id: product_ids).where.not(workspace_id: nil).distinct.pluck(:workspace_id)
    comp_ids = Component.where(product_id: product_ids).select(:id)
    Invitation.pending.where(
      "scope_workspace_id IN (:ws) OR scope_product_id IN (:pids) OR scope_component_id IN (:cids)",
      ws: ws_ids, pids: product_ids, cids: comp_ids
    ).order(created_at: :desc)
  end
end
