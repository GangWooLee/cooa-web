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

  # 표시 정체성 역방향 리졸버(리뷰 F4). 저작권 뷰(댓글 author·버전 created_by·리뷰 submitter/reviewers·
  # 제품 담당자 pm.user)는 User를 직접 렌더한다. 개명은 Account(display_name/avatar_color/job_title, tenant-scoped)에
  # 저장되므로, 여기서 account-우선으로 리졸브해 저작권 뷰까지 개명을 일관 반영한다. 읽기 전용 — users 테이블
  # 쓰기 경로는 추가하지 않는다(잠긴 도메인 원값). 폴백은 원컬럼(self[:name] 등)이라 account 미설정 = 기존 표시.
  #
  # 순환 금지(단방향 의존): 여기선 Account의 원컬럼(account&.[](:col))만 읽는다. Account#name/#avatar_color
  # 리졸버를 부르면 그쪽이 다시 user&.name/#avatar_color(=이 메서드)로 돌아 상호재귀가 된다 → 값은 같은 곳에
  # 수렴해 무한루프는 아니지만 비효율. 그래서 양쪽 리졸버 모두 상대의 "원컬럼"만 읽도록 고정한다(Account 리졸버도
  # user&.[](:name)으로 정리). has_one :account는 RLS tx 안에서 현 테넌트 계정만 보이므로(accounts는 tenant_id
  # RLS) 표시 정체성이 테넌트별 선호로 자동 한정된다 — 테넌트별 다른 표시명이 구조적으로 자명.
  def name = account&.[](:display_name).presence || self[:name]
  def avatar_color = account&.[](:avatar_color).presence || self[:avatar_color]
  def role_label = ROLE_LABELS[job_key]
  def role_short = ROLE_SHORT[job_key]
  def initial = name.to_s.first

  private

  # 직무 표시 키 — account job_title(표시 선호, User.roles.keys로 검증됨) 우선, 없으면 도메인 역할 원값(self[:role]).
  # ROLE_LABELS/ROLE_SHORT 키를 Account와 공유(같은 역할 어휘).
  def job_key = account&.[](:job_title).presence || self[:role]
end
