# 초대 랜딩(GET /invite/:token) — 티켓 확인 후 세션에 원문 토큰을 심고 소셜 로그인으로 유도.
# 무효/만료/회수 티켓은 사유를 구분하지 않는 단일 안내(열거 방지). tenant 컨텍스트는 concern이 유지.
class InvitationAcceptancesController < ApplicationController
  layout "auth"
  allow_unauthenticated_access only: :show
  skip_after_action :verify_authorized # 미인증 랜딩 — Pundit 대상 리소스 아님(sessions와 동일 관례)

  def show
    @invitation = Invitation.pending.find_by(token_digest: Invitation.digest(params[:token].to_s))
    return if @invitation.nil? # 뷰가 generic 안내 렌더

    session[:invite_token] = params[:token] # OIDC 왕복을 넘어 콜백에서 소비(reset_session 전 판독)
    @organization = Organization.find(Current.tenant_id)
  end
end
