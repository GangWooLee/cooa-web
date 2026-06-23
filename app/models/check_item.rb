class CheckItem < ApplicationRecord
  belongs_to :component_version
  enum :status, { missing: "missing", needs_check: "needs_check", done: "done" }, default: "needs_check"

  STATUS_META = {
    "missing"     => { label: "누락",      color: "#8e0300", icon: "x" },
    "needs_check" => { label: "확인 필요", color: "#e6a700", icon: "warn" },
    "done"        => { label: "완료",      color: "#84b733", icon: "check" }
  }.freeze

  def status_meta = STATUS_META[status]
end
