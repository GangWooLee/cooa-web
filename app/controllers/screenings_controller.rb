class ScreeningsController < ApplicationController
  before_action :set_version

  # ④ 인허가 스크리닝 화면
  def screening
    authorize @version, :view_screening_findings?
    @run = latest_run
    TabHistory.track(session, "s", @version.id) # 헤더 히스토리 — 스크리닝
  end

  # 스크리닝 실행(룰엔진) — ran=1로 "방금 실행" 표시(스캔 애니메이션·순차 reveal 트리거)
  def run_screening
    authorize @version, :run_screening?
    # 국가 미지정이면 실행 차단 — fact 0건으로 "적합" 거짓음성 방지(화면이 안내 배너 표시)
    return redirect_to screening_component_version_path(@version) if @country.blank?
    ScreeningService.new(@version, @country).run!(requested_by: current_user)
    redirect_to screening_component_version_path(@version, ran: 1)
  rescue ActiveRecord::RecordInvalid => e
    # 서비스 내부 tx(create!)의 검증 실패는 사용자가 조치하기 어려운 내부 오류 — 조용히 삼키지 않고
    # Rails.error로 관측한 뒤 안내(flash)로 되돌린다(E3).
    Rails.error.report(e, handled: true, source: "screenings#run_screening")
    redirect_to screening_component_version_path(@version), alert: "스크리닝 실행에 실패했습니다. 잠시 후 다시 시도해주세요."
  end

  private

  def set_version
    @version = ComponentVersion.includes(:ingredients, :label_texts, component: :product).find(params[:id])
    @product = @version.product
    @country = @product.country
    @country_label = @product.country_label
  end

  def latest_run
    @version.screening_runs.where(country: @country).order(:created_at, :id).last # id 동률 보정
  end
end
