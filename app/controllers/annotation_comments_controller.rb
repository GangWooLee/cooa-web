class AnnotationCommentsController < ApplicationController
  # 코멘트 author(연결 User)는 NOT NULL — 미브리지 계정은 도메인 액터가 없어 작성 불가. 공용 가드로 먼저
  # fail-closed 403(E4). annotations#create와 대칭(error-handling.md §4의 annotation_comments 불변 실체화).
  # non-bang save는 초장문 등 입력검증 실패를 flash로 처리하는 별개 백스톱 — 가드는 nil author를 상류 차단.
  before_action :require_domain_actor, only: %i[create]

  # 어노테이션 코멘트 스레드에 글/답글 추가
  def create
    annotation = Annotation.find(params[:annotation_id])
    authorize annotation, :leave_feedback?
    fallback = product_path(annotation.component_version.product)
    body = params[:body].to_s.strip
    return redirect_back(fallback_location: fallback) if body.blank? # 빈 코멘트는 무시(무피드백 되돌림)

    comment = annotation.comments.new(author: current_user, body: body, parent_id: params[:parent_id])
    if comment.save
      redirect_back fallback_location: fallback
    else
      redirect_back fallback_location: fallback,
                    alert: comment.errors.full_messages.to_sentence.presence || "코멘트를 저장하지 못했습니다."
    end
  end
end
