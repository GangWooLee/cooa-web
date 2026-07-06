# 초대 랜딩(GET /invite/:token) — 티켓 확인 후 세션에 원문 토큰을 심고 소셜 로그인으로 유도.
# T2 (identity-based tenant): 미인증 진입이라 세션 테넌트가 없다 → 토큰으로 초대의 테넌트를 SECURITY DEFINER
# 브리지로 해석한 뒤 그 테넌트 tx 안에서 상세를 로드·렌더한다(한 배포의 크로스 조직 초대도 열림). 무효/만료/
# 회수 티켓은 사유를 구분하지 않는 단일 안내(열거 방지) — 브리지가 pending만 해석하므로 자연히 그렇게 된다.
class InvitationAcceptancesController < ApplicationController
  layout "auth"
  allow_unauthenticated_access only: :show
  skip_after_action :verify_authorized # 미인증 랜딩 — Pundit 대상 리소스 아님(sessions와 동일 관례)

  def show
    digest = Invitation.digest(params[:token].to_s)
    tenant_id = AuthLookup.invitation_tenant(digest)
    return render(:show) if tenant_id.blank? # @invitation nil → 뷰가 generic 안내 렌더(테넌트 무의존)

    TenantContext.with_tenant(tenant_id) do
      Current.tenant_id = tenant_id
      # 표시에 필요한 스코프 연관을 프리로드해 렌더 중 지연 로드를 없앤다(그래도 렌더를 tx 안에서 수행).
      @invitation = Invitation.pending.includes(:scope_workspace, :scope_product).find_by(token_digest: digest)
      @organization = Organization.find(tenant_id) if @invitation
      session[:invite_token] = params[:token] if @invitation # OIDC 왕복 넘어 콜백이 소비(reset 전 판독)
      render :show
    end
  end
end
