# 조직 초대 티켓(Phase 3) — 1회용·만료·이메일 귀속. 수락하면 정식 멤버(역할 기반 전체 접근)이며
# 링크는 전달 수단일 뿐(파일별 공유 아님). 토큰 원문은 저장하지 않는다(digest만).
class Invitation < ApplicationRecord
  include TenantScoped
  # owner 초대 금지: brand_admin(manage_members 보유)이 owner를 발행하는 권한 상승 차단.
  INVITABLE_ROLE_KEYS = (RoleAssignment::ROLE_KEYS - %w[owner]).freeze
  TTL = 7.days

  belongs_to :organization, foreign_key: :tenant_id, inverse_of: false

  normalizes :email, with: ->(v) { v.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "형식이 올바르지 않습니다" }
  validates :role_key, inclusion: { in: INVITABLE_ROLE_KEYS, message: "은 초대할 수 없는 역할입니다" }
  validates :token_digest, presence: true, uniqueness: true
  validate :email_not_already_member, on: :create

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil).where(expires_at: Time.current..) }

  def self.digest(raw) = Digest::SHA256.hexdigest(raw.to_s)

  # 생성 + raw 토큰 1회 반환(256bit). digest만 저장하므로 이 반환값이 링크를 만들 유일한 기회.
  def self.generate!(email:, role_key:, invited_by_account_id:)
    raw = SecureRandom.urlsafe_base64(32)
    invitation = create!(email:, role_key:, invited_by_account_id:,
                         token_digest: digest(raw), expires_at: TTL.from_now)
    [ invitation, raw ]
  end

  def pending? = accepted_at.nil? && revoked_at.nil? && expires_at.future?

  # 원자 클레임 — pending 조건부 update_all이라 동시 수락은 정확히 1명만 승자(레이스/재사용 방지).
  def claim!
    self.class.where(id: id, accepted_at: nil, revoked_at: nil)
        .where(expires_at: Time.current..)
        .update_all(accepted_at: Time.current) == 1
  end

  def revoke! = update!(revoked_at: Time.current)

  private

  # 이미 멤버인 이메일은 초대 불가(생성 시점 UX 가드 — 멤버 페이지는 manage_members 보유자 전용이라
  # 이 메시지가 열거 채널이 되지 않는다). RLS가 테넌트 스코프를 보장.
  def email_not_already_member
    return if email.blank?
    errors.add(:email, "은 이미 멤버입니다") if Account.exists?(email: email)
  end
end
