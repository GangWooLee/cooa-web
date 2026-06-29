class ComparisonsController < ApplicationController
  before_action :set_versions

  # ③ 버전 비교 — 기준(이전) 버전의 어노테이션을 검토(현재) 버전에서 반영확인
  def show
    authorize @from, :view_component_version?
    authorize @to, :view_component_version? # m-3 (P2): the comparison target needs authz too, not just @from
    @annotations = @from.annotations.ordered.includes(:created_by, :resolved_by, comments: :author)
    @versions    = @component.versions_asc
    TabHistory.track(session, "c", "#{@from.id}-#{@to.id}") # 헤더 히스토리 — 버전 비교
  end

  private

  def set_versions
    @from = ComponentVersion.includes(:annotations).find(params[:from_id])
    @to   = ComponentVersion.includes(:annotations).find(params[:to_id])
    @component = @from.component
    @product   = @component.product
  end
end
