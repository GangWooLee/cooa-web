# 작업실(Workspace) CRUD (D3) — 생성(이름 + 선택 멤버 4종)·이름변경·삭제(빈 작업실만). 진입(show/GET)은
# DashboardController#index가 담당(복수 루트 트리). 인가: 작업실 컨테이너 수명주기(생성·이름변경·삭제)는
# tenant-wide manage_product 보유자(owner/brand_admin tenant-wide)만 — 조직 레코드로 authorize(WorkspacePolicy
# 신설 없이 record-독립 tenant-wide 역할 해석 재사용, 기존 "+ 새 작업실" 버튼 게이트와 동일). 스코프 admin은
# 멤버 관리만(작업실 페이지 패널). 감사(allow)를 남기므로 도메인 액터 가드 선행(E4).
class WorkspacesController < ApplicationController
  include MemberAdministration

  before_action :require_domain_actor, only: %i[create update destroy]

  def create
    authorize current_organization, :manage_product? # tenant-wide 관리자만 새 작업실 생성(스코프 admin 차단)
    workspace = Workspace.new(name: params[:name].to_s.strip, tenant_id: Current.tenant_id,
                              position: (Workspace.maximum(:position) || 0) + 1) # 새 작업실은 목록 맨 뒤
    if workspace.save
      added = add_creation_members(workspace)
      audit_workspace!("workspace.create", workspace, member_count: added)
      redirect_to workspace_path(workspace), notice: "작업실을 만들었습니다."
    else
      redirect_to root_path, alert: workspace.errors.full_messages.to_sentence.presence || "작업실을 만들지 못했습니다."
    end
  end

  def update
    workspace = Workspace.find(params[:id])
    authorize current_organization, :manage_product?
    if workspace.update(name: params[:name].to_s.strip)
      audit_workspace!("workspace.rename", workspace)
      redirect_to workspace_path(workspace), notice: "작업실 이름을 변경했습니다."
    else
      redirect_to workspace_path(workspace),
                  alert: workspace.errors.full_messages.to_sentence.presence || "이름을 변경하지 못했습니다."
    end
  end

  def destroy
    workspace = Workspace.find(params[:id])
    authorize current_organization, :manage_product?
    # 빈 작업실만 삭제. dependent: :restrict_with_exception(+ DB FK RESTRICT 백스톱)이 "제품 매달린 작업실 불가"의
    # 단일 출처 — 제품이 남아 있으면 DeleteRestrictionError → R9 flash 안내(트리 정리 선행). 성공 시 홈 복귀.
    workspace.destroy!
    audit_workspace!("workspace.destroy", workspace)
    redirect_to root_path, notice: "작업실을 삭제했습니다."
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to workspace_path(workspace),
                alert: "제품이 남아 있는 작업실은 삭제할 수 없습니다 — 먼저 모든 폴더·항목을 비워 주세요."
  end

  private

  # 생성 시 선택 멤버 → 작업실-스코프 role_assignment(팀 4종만). 폼: member_ids[]=account_id + roles[account_id]=role_key.
  # 4종 밖 역할(크래프트)·미존재/타테넌트 계정(RecordInvalid)·중복(RecordNotUnique)은 건너뛴다(작업실 생성은 유지 —
  # 멤버는 best-effort·"건너뛰기 가능"). 각 grant를 SAVEPOINT로 격리(RecordNotUnique가 바깥 RLS tx를 abort시키지 않게).
  # 반환 = 실제 추가된 멤버 수(감사용).
  def add_creation_members(workspace)
    ids = Array(params[:member_ids]).map(&:to_s).reject(&:blank?).uniq
    roles = params[:roles] || {}
    ids.sum do |aid|
      rk = roles[aid].to_s
      next 0 unless Authz::RoleLabels.workspace_role?(rk)

      RoleAssignment.transaction(requires_new: true) do
        RoleAssignment.create!(account_id: aid, tenant_id: Current.tenant_id, role_key: rk,
                               scope_type: "workspace", scope_workspace_id: workspace.id,
                               granted_by: current_account.id, granted_at: Time.current)
      end
      1
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.info("[workspace.create] skip member account=#{aid} role=#{rk}: #{e.class}")
      0
    end
  end

  def audit_workspace!(action, workspace, member_count: nil)
    after = { name: workspace.name }
    after[:member_count] = member_count if member_count
    AuditLog.record!(action: action, resource_type: "Workspace", resource_id: workspace.id, outcome: "allow",
                     after: after, request_id: request.request_id, source_ip: request.remote_ip,
                     user_agent: request.user_agent)
  end
end
