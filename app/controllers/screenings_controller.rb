class ScreeningsController < ApplicationController
  before_action :set_version

  # ④ 인허가 스크리닝 화면
  def screening
    @run = latest_run
  end

  # 스크리닝 실행(룰엔진)
  def run_screening
    ScreeningService.new(@version, @country).run!(requested_by: current_user)
    redirect_to screening_component_version_path(@version)
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
