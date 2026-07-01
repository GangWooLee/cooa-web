# 버전 리뷰 요청(리프레임 — ADR-002 §5.3 후신). 규제 전자서명이 아니라 GitHub PR-approve식 경량 검토:
# 리뷰어가 한 버전(직전 대비 변경)이 제대로 반영됐는지 "검토 확인" 또는 "변경 요청"한다. 선형 체인이라
# merge 없음. 신원기반 SoD(리뷰어≠요청자)는 정책에서, 리뷰 중 변경(stale) 차단은 confirm_review!에서.
# 한 버전(screening_run)당 1요청 (UNIQUE(tenant_id, screening_run_id)). 규제 사인오프는 고객 내부 시스템.
class ApprovalRequest < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending reviewed changes_requested cancelled].freeze
  TERMINAL = %w[reviewed changes_requested cancelled].freeze

  StaleReviewedTuple = Class.new(StandardError) # 리뷰 중 콘텐츠 변경 재검 실패(TOCTOU 경량 가드)

  belongs_to :screening_run
  belongs_to :submitter, class_name: "User"
  has_many :approval_steps, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :market, presence: true

  def pending? = status == "pending"
  def reviewed? = status == "reviewed"
  def changes_requested? = status == "changes_requested"
  def terminal? = TERMINAL.include?(status)

  # 리뷰 요청 + 콘텐츠 스냅샷 캡처. run당 멱등: terminal이면 그대로 반환, 아니면 pending. (M1 하드 게이트
  # 폐지 — 적격 리뷰어 부재는 컨트롤러/UI의 소프트 안내로 처리.)
  def self.submit_for!(screening_run, submitter_id:)
    req = find_or_initialize_by(tenant_id: Current.tenant_id, screening_run_id: screening_run.id)
    return req if req.terminal?

    req.assign_attributes(submitter_id: submitter_id, market: screening_run.country,
                          reviewed_at: Time.current, status: "pending", **ReviewedTuple.capture(screening_run))
    req.save!
    req
  end

  # SoD(리뷰어≠요청자)는 정책이 먼저 확인. 리뷰 중 콘텐츠 변경(stale)은 여기서 원자적으로 재검:
  # component_version을 FOR UPDATE로 잠그고 스냅샷 재비교 → 확인-커밋 사이 콘텐츠 발산 차단(TOCTOU).
  # 발산 시 StaleReviewedTuple. (전체 편집/재스크리닝 락 조율은 Phase 2b.)
  def confirm_review!(reviewer_id:)
    transaction do
      screening_run.component_version.lock! # FOR UPDATE — 동시 편집/재스크리닝과 직렬화
      raise StaleReviewedTuple if ReviewedTuple.stale?(self)
      approval_steps.create!(approver_id: reviewer_id, decision: "confirmed", acted_at: Time.current)
      update!(status: "reviewed")
    end
  end

  def request_changes!(reviewer_id:, reason: nil)
    transaction do
      approval_steps.create!(approver_id: reviewer_id, decision: "changes_requested", reason: reason, acted_at: Time.current)
      update!(status: "changes_requested")
    end
  end
end
