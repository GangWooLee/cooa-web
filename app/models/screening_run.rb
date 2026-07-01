class ScreeningRun < ApplicationRecord
  include TenantScoped
  include Decidable

  belongs_to :component_version
  belongs_to :requested_by, class_name: "User", optional: true
  has_many :screening_findings, -> { order(:position, :id) }, dependent: :destroy

  # 'approved'는 은퇴한 screening-레벨 승인 값 — 리프레임 후 제거(리뷰는 approval_requests가 담당).
  enum :status, { pending: "pending", completed: "completed" }, default: "completed"
  enum :decision, { ok: "ok", warning: "warning", violation: "violation", unable: "unable" }, prefix: :decision

  def country_label = ApplicationRecord.country_label(country)
end
