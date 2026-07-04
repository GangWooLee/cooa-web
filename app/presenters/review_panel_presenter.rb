# 버전 리뷰 패널의 계산 로직(선언적·단위테스트 가능). _review_panel의 인라인 분기/쿼리를 여기로 추출.
# 정책 게이트(submit_for_approval?/confirm_review?)는 pundit 컨텍스트가 필요해 뷰에 남긴다.
class ReviewPanelPresenter
  attr_reader :version, :request, :open_feedback_count

  def initialize(version:, request:, open_feedback_count:)
    @version = version
    @request = request
    @open_feedback_count = open_feedback_count
  end

  # :none(요청 전) / :pending / :reviewed
  def state = request.nil? ? :none : request.status.to_sym

  def open_feedback? = open_feedback_count.positive?

  # 검토 확인 시 미해결 피드백 소프트 경고(advisory·클라이언트 turbo_confirm). 없으면 nil.
  def confirm_warning
    "미해결 피드백 #{open_feedback_count}개가 있습니다. 그래도 검토 확인하시겠습니까?" if open_feedback?
  end

  def confirmed_step = request&.approval_steps&.find_by(decision: "confirmed")

  def requested_reviewers = request&.requested_reviewers || []

  def waiting_message
    names = requested_reviewers.map(&:name)
    names.any? ? "#{names.join(", ")}님의 검토를 기다리는 중입니다." : "검토 가능한 리뷰어를 기다리는 중입니다."
  end

  # 리뷰어 지정 후보 = 버전의 브랜드 루트(팀 단위) 서브트리 스코프 grant + tenant-wide grant 보유 계정의
  # 연결 User(Stage 4 T2 — 권한 평면 기준, 자신 제외). 표시 명부(product_member)가 아니라 role_assignment
  # 가 후보를 결정한다 → 화이트리스트(sanitized_reviewer_ids)와 단일 출처(ReviewCandidates).
  def candidate_members(current_user)
    ReviewCandidates.users_for(version, exclude_user_id: current_user&.id)
  end
end
