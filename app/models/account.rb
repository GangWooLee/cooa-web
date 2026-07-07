# Login identity, single-tenant (ADR-002 §5.1). The authenticated principal in Phase 2.
# Email is unique PER TENANT (see migration) — never global.
class Account < ApplicationRecord
  STATUSES = %w[invited active suspended deprovisioned].freeze
  DEFAULT_AVATAR_COLOR = "#8e0300".freeze
  # 셀프 프로필 편집 UI가 제공하는 큐레이션 스와치(브랜드 정합). 저장은 hex 문자열.
  AVATAR_SWATCHES = %w[#8e0300 #b23a2e #c9822b #5f8f2e #2f6f6b #2d5a8e #5b3f8e #3d3d3d].freeze

  belongs_to :organization, foreign_key: :tenant_id, inverse_of: :accounts
  # Strategy B (Phase 2a-1): the linked User is the domain "person" (owner_id / *_by_id FK target) and
  # the display source. Optional so Phase 2b Keycloak JIT can create accounts before/without a User.
  belongs_to :user, optional: true
  has_many :role_assignments, dependent: :destroy

  before_update :guard_last_owner_on_deactivate # P6 #3: refuse suspend/deprovision of the last active owner
  before_destroy :guard_last_owner_on_destroy

  validates :email, presence: true
  validates :status, inclusion: { in: STATUSES }
  # 프로필 폼의 "비움 = 기본값 사용" 의미론: 빈 문자열을 nil로 정규화해 폴백 해석(display resolver)이 살아난다.
  normalizes :display_name, :avatar_color, :job_title, with: ->(v) { v.presence }
  # 셀프 프로필 편집분(계정 설정) — 전부 선택(nil=폴백). hex 6자리 · 직무는 User 역할 enum 키 · 이름 상한.
  validates :avatar_color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "색상 형식이 올바르지 않습니다" }, allow_blank: true
  validates :job_title, inclusion: { in: User.roles.keys, message: "직무 값이 올바르지 않습니다" }, allow_blank: true
  validates :display_name, length: { maximum: 80, message: "이름은 80자 이내여야 합니다" }, allow_blank: true
  # 바인딩 불변식: subject는 provider 네임스페이스 안에서만 의미(Google sub ≠ KC sub). 쌍으로만 세팅.
  validates :idp_provider, presence: true, if: -> { idp_subject.present? }
  validates :idp_subject,  presence: true, if: -> { idp_provider.present? }

  scope :active, -> { where(status: "active") }

  # Display identity — account-first, user-fallback. Self-service profile edits (display_name/avatar_color/
  # job_title, tenant-scoped on accounts) win over the global User person. account-subject views (sidebar,
  # member lists) render via these resolvers; content-authorship views resolve the SAME preference via
  # User's reverse resolver (User#name etc, reflecting this account under RLS).
  # 순환 금지(단방향 의존): 폴백은 User의 원컬럼(user&.[](:col))만 읽는다 — user&.name/#avatar_color(리졸버)를
  # 부르면 그쪽이 다시 account를 봐 상호재귀가 된다(같은 값 수렴이라 무한루프는 아니나 비효율). User 쪽 리졸버도
  # account 원컬럼만 읽어 대칭을 이룬다.
  def name = self[:display_name].presence || user&.[](:name)
  def avatar_color = self[:avatar_color].presence || user&.[](:avatar_color) || DEFAULT_AVATAR_COLOR
  def job_key = self[:job_title].presence || user&.[](:role)
  def role_label = job_key && (User::ROLE_LABELS[job_key] || job_key)
  def role_short = job_key && (User::ROLE_SHORT[job_key] || job_key)

  def active? = status == "active"

  # SoD identity bridge: actor_id must live in the domain FK space (User bigint), not the Account uuid,
  # or `requested_by_id != actor_id` is always true (self-approval fail-open). See AccessContext#actor_id.
  def domain_user_id = user_id

  # Revoke-all: every bump invalidates outstanding sessions/tokens (ADR-003 §3.3). Checked per-request.
  def bump_token_version! = increment!(:token_version)

  private

  # Suspend/deprovision an account that is CURRENTLY an active owner → must leave another active owner.
  def guard_last_owner_on_deactivate
    return unless status_changed? && status_was == "active" && !active?
    LastOwnerGuard.ensure_owner_remains!(tenant_id, id) if owner_grant?
  end

  # Destroy cascades role_assignments (dependent: :destroy) — the RoleAssignment guard also fires — but
  # guard here too so the refusal is explicit regardless of callback ordering.
  def guard_last_owner_on_destroy
    LastOwnerGuard.ensure_owner_remains!(tenant_id, id) if active? && owner_grant?
  end

  def owner_grant?
    role_assignments.active.tenant_wide.exists?(role_key: "owner")
  end
end
