# 버전 리뷰의 신원기반 SoD(ADR-002 §8.2 / M2): 리뷰어는 verb를 보유하고, 요청은 pending이며, 리뷰어가
# 요청자(owner 포함)와 달라야 한다 = "자기 변경 자기 확인 금지"(GitHub 규범). actor_id는 브리지된 도메인
# user_id(User bigint) — nil(미연결 Account)이면 fail-CLOSED. 내부 verb 키(approve/reject)는 ADR-002 §6
# 권한 상한 식별자 그대로(=검토확인/변경요청 능력). stale 재검·상태 전이는 모델/컨트롤러가 처리.
class ApprovalRequestPolicy < ApplicationPolicy
  def confirm_review?
    reviewer_capable?(:approve) && record.pending? && actor_present? && submitter_distinct?
  end

  private

  # 소프트 게이트(리프레임 철학·가산적): 요청받은 리뷰어 OR 테넌트 owner/approver 폴백. "요청받음 = 그
  # 리뷰 한정 검토 권한"이라 담당자(approve verb 없어도)가 지정되면 확인 가능. SoD(≠요청자)만 하드.
  def reviewer_capable?(fallback_verb) = requested_reviewer? || can?(fallback_verb)
  def requested_reviewer? = actor_present? && record.requested_reviewer_ids.include?(context.actor_id)
  def actor_present? = context.actor_id.present?
  def submitter_distinct? = record.submitter_id != context.actor_id
end
