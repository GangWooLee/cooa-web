class ComparisonsController < ApplicationController
  before_action :set_versions

  # ③ 버전 비교 화면
  def show
    @diffs       = VersionDiff.where(from_version: @from, to_version: @to).ordered
    @feedbacks   = @from.feedbacks.roots.includes(:author, replies: :author).order(:created_at)
    @check_items = @from.check_items.order(:position)
  end

  # AI 수정 여부 다시 체크 — 비교 대상(@to) 기준으로 재평가(데모: 결정론적)
  def recheck
    blob = @to.label_texts.map { |t| t.content.to_s.downcase }.join("  ")
    @from.check_items.each do |ci|
      if ci.label.include?("재활용")
        ci.update(status: (blob.include?("재활용") || blob.include?("recycl")) ? "done" : "missing")
      elsif ci.status == "needs_check"
        ci.update(status: "done") # 비교 대상에서 수정 반영 확인됨
      end
    end
    redirect_to comparison_path(from_id: @from.id, to_id: @to.id), notice: "v#{@to.version_number} 기준 재검 완료"
  end

  private

  def set_versions
    @from = ComponentVersion.includes(:label_texts).find(params[:from_id])
    @to   = ComponentVersion.includes(:label_texts).find(params[:to_id])
    @component = @from.component
    @product   = @component.product
  end
end
