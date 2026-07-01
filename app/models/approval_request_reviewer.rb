# 리뷰 요청의 지정 리뷰어(join). "요청받음 = 그 리뷰 한정 검토 권한"(리프레임)의 저장소.
# reviewer는 전역 User(bigint) — submitter_id/approver_id와 동일 공간(SoD 비교용). tenant RLS 격리.
class ApprovalRequestReviewer < ApplicationRecord
  include TenantScoped

  belongs_to :approval_request
  belongs_to :reviewer, class_name: "User"
end
