class AnnotationsController < ApplicationController
  # 아트워크 위 바운딩박스 피드백 생성 (드래그 → %좌표 + 첫 코멘트)
  def create
    version = ComponentVersion.find(params[:component_version_id])
    authorize version, :leave_feedback?
    annotation = version.annotations.create!(
      box_x: params[:box_x], box_y: params[:box_y], box_w: params[:box_w], box_h: params[:box_h],
      category: params[:category].presence || "기타",
      created_by: current_user,
      seq: (version.annotations.maximum(:seq) || 0) + 1
    )
    annotation.comments.create!(author: current_user, body: params[:body]) if params[:body].present?
    redirect_back fallback_location: product_path(version.product)
  end

  # 다음 버전에서 반영 확인 → 해결
  def resolve
    annotation = Annotation.find(params[:id])
    authorize annotation, :resolve_feedback?
    annotation.update!(status: "resolved", resolved_by: current_user, resolved_at: Time.current,
                       resolved_in_version_id: params[:resolved_in_version_id])
    redirect_back fallback_location: root_path
  end

  def reopen
    annotation = Annotation.find(params[:id])
    authorize annotation, :resolve_feedback?
    annotation.update!(status: "open", resolved_by: nil, resolved_at: nil, resolved_in_version_id: nil)
    redirect_back fallback_location: root_path
  end
end
