class AnnotationCommentsController < ApplicationController
  # 어노테이션 코멘트 스레드에 글/답글 추가
  def create
    annotation = Annotation.find(params[:annotation_id])
    authorize annotation, :leave_feedback?
    if params[:body].to_s.strip.present?
      annotation.comments.create!(author: current_user, body: params[:body].strip, parent_id: params[:parent_id])
    end
    redirect_back fallback_location: product_path(annotation.component_version.product)
  end
end
