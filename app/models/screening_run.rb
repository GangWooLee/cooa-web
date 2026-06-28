class ScreeningRun < ApplicationRecord
  include TenantScoped
  include Decidable

  belongs_to :component_version
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :screening_findings, -> { order(:position, :id) }, dependent: :destroy

  enum :status, { pending: "pending", completed: "completed", approved: "approved" }, default: "completed"
  enum :decision, { ok: "ok", warning: "warning", violation: "violation", unable: "unable" }, prefix: :decision

  def country_label = ApplicationRecord.country_label(country)
end
