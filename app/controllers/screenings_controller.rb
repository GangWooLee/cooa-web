class ScreeningsController < ApplicationController
  before_action :set_version

  # ④ 인허가 스크리닝 화면
  def screening
    @run = latest_run
    TabHistory.track(session, "s", @version.id) # 헤더 히스토리 — 스크리닝
  end

  # 스크리닝 실행(룰엔진) — ran=1로 "방금 실행" 표시(스캔 애니메이션·순차 reveal 트리거)
  def run_screening
    # 국가 미지정이면 실행 차단 — fact 0건으로 "적합" 거짓음성 방지(화면이 안내 배너 표시)
    return redirect_to screening_component_version_path(@version) if @country.blank?
    ScreeningService.new(@version, @country).run!(requested_by: current_user)
    redirect_to screening_component_version_path(@version, ran: 1)
  end

  # RA 승인
  def approve_screening
    latest_run&.update(status: "approved", approved_by: current_user, approved_at: Time.current)
    redirect_to screening_component_version_path(@version)
  end

  private

  def set_version
    @version = ComponentVersion.includes(:ingredients, :label_texts, component: :product).find(params[:id])
    @product = @version.product
    @country = @product.country
    @country_label = @product.country_label
  end

  def latest_run
    @version.screening_runs.where(country: @country).order(:created_at).last
  end
end
