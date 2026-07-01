# 버전 리뷰 요청(리프레임 후속). 규제 전자서명이 아니라 경량 검토: 리뷰어가 한 버전을 "검토 확인"하거나
# 피드백(annotation)을 남긴다. "고쳐야 함"의 실체는 피드백이 유일 채널(변경 요청 상태 폐지). 리뷰는 버전에
# 붙는다(component_version 앵커) — AI 사전심사는 RA/담당자가 검토 중 수행하므로 디자이너는 스크리닝 없이도
# 리뷰를 요청할 수 있어야 함. 버전당 1요청. SoD(리뷰어≠요청자)=정책, 리뷰 중 콘텐츠 변경(stale)=confirm_review!.
class ApprovalRequest < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending reviewed].freeze
  TERMINAL = %w[reviewed].freeze

  StaleReviewedTuple = Class.new(StandardError) # 리뷰 중 콘텐츠 변경 재검 실패(TOCTOU 경량 가드)

  belongs_to :component_version
  belongs_to :submitter, class_name: "User"
  has_many :approval_steps, dependent: :destroy
  has_many :approval_request_reviewers, dependent: :destroy
  # 지정 리뷰어(요청받은 사람). requested_reviewer_ids = User bigint 배열(정책 ACL·수신함에서 사용).
  has_many :requested_reviewers, through: :approval_request_reviewers, source: :reviewer

  validates :status, inclusion: { in: STATUSES }

  def pending? = status == "pending"
  def reviewed? = status == "reviewed"
  def terminal? = TERMINAL.include?(status)

  # 리뷰 요청 + 콘텐츠 스냅샷 캡처. 버전당 멱등: terminal(reviewed)이면 그대로 반환, 아니면 pending.
  # (스크리닝 선행 불요 — RA가 검토 중 수행.)
  def self.submit_for!(component_version, submitter_id:, reviewer_ids: [])
    req = find_or_initialize_by(tenant_id: Current.tenant_id, component_version_id: component_version.id)
    return req if req.terminal?

    transaction do
      req.assign_attributes(submitter_id: submitter_id, requested_at: Time.current,
                            status: "pending", **ReviewedTuple.capture(component_version))
      req.save!
      req.sync_requested_reviewers!(reviewer_ids, exclude: submitter_id)
    end
    req
  end

  # 지정 리뷰어 집합 재구성(1..N). 요청자 자신은 제외(SoD 보완). ids는 User bigint. 멤버십 검증은 컨트롤러.
  def sync_requested_reviewers!(ids, exclude:)
    want = Array(ids).map(&:to_i).uniq - [exclude].compact
    have = approval_request_reviewers.pluck(:reviewer_id)
    approval_request_reviewers.where(reviewer_id: have - want).delete_all if (have - want).any?
    (want - have).each { |rid| approval_request_reviewers.create!(reviewer_id: rid) }
  end

  # SoD는 정책이 먼저 확인. 리뷰 중 콘텐츠 변경(stale)은 여기서 원자적으로 재검: 버전을 FOR UPDATE로 잠그고
  # 스냅샷 재비교 → 확인-커밋 사이 콘텐츠 발산 차단(TOCTOU). 발산 시 StaleReviewedTuple.
  def confirm_review!(reviewer_id:)
    transaction do
      component_version.lock! # FOR UPDATE — 동시 편집과 직렬화
      raise StaleReviewedTuple if ReviewedTuple.stale?(self)
      approval_steps.create!(approver_id: reviewer_id, decision: "confirmed", acted_at: Time.current)
      update!(status: "reviewed")
    end
  end
end
