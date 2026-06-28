class User < ApplicationRecord
  enum :role, { designer: "designer", pm: "pm", ra: "ra", scm: "scm" }, default: "pm"

  ROLE_LABELS = { "designer" => "디자이너", "pm" => "PM", "ra" => "RA", "scm" => "SCM" }.freeze
  ROLE_SHORT  = { "designer" => "D", "pm" => "PM", "ra" => "RA", "scm" => "SCM" }.freeze

  has_many :product_members, dependent: :destroy
  has_many :products, through: :product_members
  has_many :owned_products, class_name: "Product", foreign_key: :owner_id, dependent: :nullify
  # Phase 2a-1 (Strategy B): the auth identity that logs in as this person. nullify on delete keeps
  # the Account row (login) even if the demo person record is removed.
  has_one :account, dependent: :nullify

  def role_label = ROLE_LABELS[role]
  def role_short = ROLE_SHORT[role]
  def initial = name.to_s.first
end
