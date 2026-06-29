# Approval aggregate (ADR-002 §5.3) — the regulatory sign-off, independent of the screening evidence.
# Signs the C1 reviewed-tuple (what the RA reviewed), enforces M1 (eligible-approver) at submit and
# M2 (identity SoD) at approve. One request per screening_run (UNIQUE(tenant_id, screening_run_id)).
class ApprovalRequest < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending blocked_no_approver approved rejected cancelled].freeze
  TERMINAL = %w[approved rejected cancelled].freeze

  belongs_to :screening_run
  belongs_to :submitter, class_name: "User"
  has_many :approval_steps, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :market, presence: true

  def pending? = status == "pending"
  def terminal? = TERMINAL.include?(status)

  # M1 + C1 capture. Idempotent per run: re-submitting a blocked_no_approver request re-evaluates and may
  # flip to pending; a terminal request is returned untouched. The reviewed-tuple is captured regardless
  # of M1 (it records what WOULD be reviewed); status reflects whether an eligible approver exists.
  def self.submit_for!(screening_run, submitter_id:)
    req = find_or_initialize_by(tenant_id: Current.tenant_id, screening_run_id: screening_run.id)
    return req if req.terminal?

    req.assign_attributes(submitter_id: submitter_id, market: screening_run.country,
                          reviewed_at: Time.current, **ReviewedTuple.capture(screening_run))
    req.status = EligibleApproverService.any?(market: req.market, exclude_user_id: submitter_id) ? "pending" : "blocked_no_approver"
    req.save!
    req
  end

  # M2 (SoD) + C1 (staleness) are checked by the policy/controller BEFORE these run.
  def approve!(approver_id:)
    transaction do
      approval_steps.create!(approver_id: approver_id, decision: "approved", meaning: "approved", acted_at: Time.current)
      update!(status: "approved")
    end
  end

  def reject!(approver_id:, reason: nil)
    transaction do
      approval_steps.create!(approver_id: approver_id, decision: "rejected", meaning: "rejected", reason: reason, acted_at: Time.current)
      update!(status: "rejected")
    end
  end
end
