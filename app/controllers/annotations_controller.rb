class AnnotationsController < ApplicationController
  # 피드백 작성/해소는 작성자(연결 User)에 귀속된다 — annotation_comments.author는 NOT NULL이라 미브리지
  # 계정의 첫 코멘트 create!가 500을 낸다. 공용 가드로 먼저 fail-closed 403(E4).
  before_action :require_domain_actor, only: %i[create resolve reopen]

  # 아트워크 위 바운딩박스 피드백 생성 (드래그 → %좌표 + 첫 코멘트)
  def create
    version = ComponentVersion.find(params[:component_version_id])
    authorize version, :leave_feedback?
    annotation = version.annotations.new(
      box_x: params[:box_x], box_y: params[:box_y], box_w: params[:box_w], box_h: params[:box_h],
      category: params[:category].presence || "기타",
      created_by: current_user,
      seq: (version.annotations.maximum(:seq) || 0) + 1
    )
    # 어노테이션 + 첫 코멘트를 원자적으로 저장. require_domain_actor가 author 존재를 보장하므로 남는 실패
    # 모드는 입력 검증(코멘트 본문 길이 2000 등)뿐 — RecordInvalid는 롤백 후 flash로 안내(S1·E3 정합, 500 방지).
    #
    # requires_new(=SAVEPOINT): 요청은 이미 RLS 트랜잭션 안(Authentication#scope_to_tenant). 평범한 중첩
    # transaction은 세이브포인트 없이 바깥 tx에 JOIN되므로(Rails가 yield만) 첫 코멘트 create!가 RecordInvalid를
    # 던져도 이미 INSERT된 annotation.save!가 롤백되지 않는다 → rescue가 예외를 삼키면 바깥 RLS tx가 그대로
    # 커밋되어 코멘트 없는 댕글링 어노테이션이 남는다. 세이브포인트로 격리 → 위반 시 save!까지 함께 롤백.
    # (confirm_review!·claim add_reviewer!·role_assignments create와 동일 관례.)
    ActiveRecord::Base.transaction(requires_new: true) do
      annotation.save!
      annotation.comments.create!(author: current_user, body: params[:body]) if params[:body].present?
    end
    redirect_back fallback_location: product_path(version.product)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: product_path(version.product),
                  alert: e.record.errors.full_messages.to_sentence.presence || "피드백을 저장하지 못했습니다."
  end

  # 다음 버전에서 반영 확인 → 해결
  def resolve
    annotation = Annotation.find(params[:id])
    authorize annotation, :resolve_feedback?
    if annotation.update(status: "resolved", resolved_by: current_user, resolved_at: Time.current,
                         resolved_in_version_id: params[:resolved_in_version_id])
      redirect_back fallback_location: root_path
    else
      redirect_back fallback_location: root_path,
                    alert: annotation.errors.full_messages.to_sentence.presence || "상태를 변경하지 못했습니다."
    end
  end

  def reopen
    annotation = Annotation.find(params[:id])
    authorize annotation, :resolve_feedback?
    if annotation.update(status: "open", resolved_by: nil, resolved_at: nil, resolved_in_version_id: nil)
      redirect_back fallback_location: root_path
    else
      redirect_back fallback_location: root_path,
                    alert: annotation.errors.full_messages.to_sentence.presence || "상태를 변경하지 못했습니다."
    end
  end
end
