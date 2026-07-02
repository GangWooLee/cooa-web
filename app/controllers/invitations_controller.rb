# 초대 생성/회수 — manage_members(owner/brand_admin) 게이트. raw 토큰 링크는 생성 응답에서만
# 존재(digest만 저장 — 재표시 불가, 재발급=회수+신규). 링크는 flash 경유(URL/로그 미노출).
class InvitationsController < ApplicationController
  def create
    authorize current_organization, :manage_members?
    invitation, raw = Invitation.generate!(
      email: params[:email], role_key: params[:role_key],
      invited_by_account_id: current_account.id
    )
    AuditLog.record!(action: "invitation.create", resource_type: "Invitation",
                     resource_id: nil, outcome: "allow", # bigint 도메인 공간 — uuid는 after로
                     after: { invitation_id: invitation.id, email: invitation.email, role_key: invitation.role_key },
                     request_id: request.request_id, source_ip: request.remote_ip,
                     user_agent: request.user_agent)
    # 메일 자동발송 확장점: raw가 존재하는 유일한 시점이 여기다.
    # InvitationMailer.with(invitation:, raw_token: raw).invite.deliver_later
    flash[:invite_link] = invite_url(raw)
    redirect_to members_path, notice: "초대를 만들었습니다 — 링크를 복사해 전달하세요."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to members_path, alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to members_path, alert: "이 이메일로 대기 중인 초대가 이미 있습니다 — 기존 초대를 취소 후 재발급하세요."
  end

  def destroy
    authorize current_organization, :manage_members?
    invitation = Invitation.find(params[:id])
    if invitation.accepted_at.present?
      redirect_to members_path, alert: "이미 수락된 초대는 취소할 수 없습니다."
    else
      invitation.revoke!
      AuditLog.record!(action: "invitation.revoke", resource_type: "Invitation",
                       resource_id: nil, outcome: "allow", after: { invitation_id: invitation.id },
                       request_id: request.request_id, source_ip: request.remote_ip,
                       user_agent: request.user_agent)
      redirect_to members_path, notice: "초대를 취소했습니다."
    end
  end

  private

  def current_organization = Organization.find(Current.tenant_id)
end
