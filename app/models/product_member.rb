class ProductMember < ApplicationRecord
  include TenantScoped
  belongs_to :product
  belongs_to :user
  # role은 자유 문자열(역할명 자유 입력). 알려진 키는 약어/라벨, 그 외는 원문 폴백.

  def role_label = User::ROLE_LABELS[role] || role
  def role_short = User::ROLE_SHORT[role] || role
end
