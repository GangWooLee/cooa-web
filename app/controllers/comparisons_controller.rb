class ComparisonsController < ApplicationController
  before_action :set_versions

  # ③ 버전 비교 — 기준(이전) 버전의 어노테이션을 검토(현재) 버전에서 반영확인
  def show
    authorize @from, :view_component_version?
    authorize @to, :view_component_version? # m-3 (P2): the comparison target needs authz too, not just @from
    # created_by·댓글 author는 비교 화면에서 표시 리졸버(account-우선)를 타므로 :account까지 프리로드(R5).
    # resolved_by는 이 뷰에서 이름 렌더 없음(상태 로직만) — 확장 불요. resolved_in_version은 반영완료 표기의
    # vlabel을 읽으므로 프리로드(누락 시 반영건당 component_versions 단건 N+1).
    @annotations = @from.annotations.ordered.includes({ created_by: :account }, :resolved_by, :resolved_in_version, comments: { author: :account })
    @versions    = @component.versions_asc
    TabHistory.track(session, "c", "#{@from.id}-#{@to.id}") # 헤더 히스토리 — 버전 비교
  end

  private

  def set_versions
    # annotations는 show가 별도 정렬·프리로드 쿼리로만 소비(@to 것은 미사용) — 이중 로드 제거.
    # 첨부는 뷰어 src·PDF 분기가 즉시 참조하므로 blob까지 프리로드(PERF-8).
    @from = ComponentVersion.with_attached_artwork.find(params[:from_id])
    @to   = ComponentVersion.with_attached_artwork.find(params[:to_id])
    @component = @from.component
    @product   = @component.product
  end
end
