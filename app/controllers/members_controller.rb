# 조직 멤버 로스터 + pending 초대 목록. 읽기=list_tenant_accounts, 초대 관리=manage_members(뷰 게이트).
# RLS가 테넌트 스코프를 보장 — 쿼리에 tenant_id 명시 불필요.
class MembersController < ApplicationController
  def index
    authorize current_organization, :list_tenant_accounts?
    @accounts    = Account.includes(:user, :role_assignments).order(:created_at)
    @invitations = Invitation.pending.order(created_at: :desc)
    @can_manage  = policy(current_organization).manage_members?
  end

  private

  def current_organization = Organization.find(Current.tenant_id)
end
