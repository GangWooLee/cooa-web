class FeedbacksController < ApplicationController
  # ③ 피드백 아카이빙 — 코멘트 추가
  def create
    @version = ComponentVersion.find(params[:component_version_id])
    body = params[:body].to_s.strip
    @feedback = @version.feedbacks.create!(author: current_user, body: body) if body.present?

    respond_to do |format|
      format.turbo_stream { @feedback ? render(:create) : head(:no_content) }
      format.html { redirect_back fallback_location: product_path(@version.product) }
    end
  end
end
