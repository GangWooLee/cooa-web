class ProductMember < ApplicationRecord
  belongs_to :product
  belongs_to :user
  enum :role, { designer: "designer", pm: "pm", ra: "ra", scm: "scm" }

  def role_label = User::ROLE_LABELS[role]
  def role_short = User::ROLE_SHORT[role]
end
