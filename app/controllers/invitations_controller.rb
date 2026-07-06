# 초대 생성/회수 — manage_members(owner/brand_admin) 게이트. raw 토큰 링크는 생성 응답에서만
# 존재(digest만 저장 — 재표시 불가, 재발급=회수+신규). 링크는 flash 경유(URL/로그 미노출).
class InvitationsController < ApplicationController
  include MemberAdministration

  # 초대 생성/회수는 감사(allow)를 남긴다 — 도메인 액터(연결 User) 없는 계정이면 AuditLog.record!가
  # fail-closed로 raise(500). 공용 가드로 먼저 fail-closed 403(E4).
  before_action :require_domain_actor, only: %i[create destroy]

  def create
    # 스코프 초대: scope_workspace_id(작업실) > scope_product_id(제품) > tenant-wide. 2단 인가(T3): scoped
    # brand_admin은 "대상 레코드"로 authorize → 관할 밖/tenant-wide 발급은 자연 deny(403·감사).
    scope = resolve_member_scope
    authorize_member_write!(scope[:target])
    # D4: 작업실/제품 스코프 초대는 팀 역할 4종만 — 전사 전용 역할 위조 발급 차단(R9 flash+redirect).
    unless scoped_role_permitted?(scope, params[:role_key].to_s)
      return redirect_to member_admin_redirect, alert: "이 역할은 작업실에 초대할 수 없습니다 — 관리자·멤버·뷰어·외부 협력 중에서 선택하세요."
    end
    # 모델 검증이 백스톱(교차테넌트/미존재·역할 정합은 Invitation 검증에서 거부 → RecordInvalid rescue로 안내).
    # 발급+감사는 공용(MemberAdministration#create_scoped_invitation!) — workspace_memberships 자동분기와 공유.
    _invitation, raw = create_scoped_invitation!(email: params[:email], role_key: params[:role_key], scope: scope)
    # 메일 자동발송 확장점: raw가 존재하는 유일한 시점이 여기다.
    # InvitationMailer.with(invitation:, raw_token: raw).invite.deliver_later
    flash[:invite_link] = invite_url(raw)
    redirect_to member_admin_redirect, notice: "초대를 만들었습니다 — 링크를 복사해 전달하세요."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to member_admin_redirect, alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[idempotent] duplicate pending invitation ignored tenant=#{Current.tenant_id} role=#{params[:role_key]}")
    redirect_to member_admin_redirect, alert: "이 이메일로 대기 중인 초대가 이미 있습니다 — 기존 초대를 취소 후 재발급하세요."
  end

  def destroy
    invitation = Invitation.find(params[:id])
    # 2단 인가(T3): scoped admin은 자기 관할 스코프 초대만 회수(스코프 대표 레코드로 authorize).
    authorize_member_write!(scope_authorize_target(invitation))
    if invitation.accepted_at.present?
      redirect_to member_admin_redirect, alert: "이미 수락된 초대는 취소할 수 없습니다."
    else
      invitation.revoke!
      record_member_audit!("invitation.revoke", "Invitation", invitation_id: invitation.id)
      redirect_to member_admin_redirect, notice: "초대를 취소했습니다."
    end
  end
end
