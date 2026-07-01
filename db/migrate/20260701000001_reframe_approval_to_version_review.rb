# 리프레임(2026-07-01): 규제 전자서명/승인 → 경량 "버전 리뷰". 오버스텝이던 의미층을 들어낸다.
#   - accounts: step-up TOTP 팩터 제거(전자서명 재인증 폐지)
#   - approval_steps: Part-11 서명 증거(meaning·re_auth·signed_c1_digest) 제거 — 행은 "리뷰어 확인" 레코드로 남음
#   - approval_requests: 규제 스냅샷(룰셋/엔진/면책 버전·verdict) 제거 — content+artifact 해시는 "리뷰 중 변경 감지"
#     경량 가드로 유지(reviewed_content_snapshot_hash·reviewed_artifact_digest는 보존).
# 컬럼 드롭뿐이라 RLS/grant/composite-FK는 불변. owner 역할로 실행(COOA_DB_USER).
class ReframeApprovalToVersionReview < ActiveRecord::Migration[8.1]
  def up
    remove_column :accounts, :totp_secret
    remove_column :accounts, :totp_registered_at

    remove_column :approval_steps, :meaning
    remove_column :approval_steps, :re_auth_at
    remove_column :approval_steps, :re_auth_factor
    remove_column :approval_steps, :signed_c1_digest

    remove_column :approval_requests, :ruleset_version
    remove_column :approval_requests, :engine_version
    remove_column :approval_requests, :disclaimer_version
    remove_column :approval_requests, :verdict_snapshot
  end

  # best-effort 되돌리기(nullable 재추가 — NOT NULL 원복은 backfill 필요라 생략)
  def down
    add_column :accounts, :totp_secret, :string
    add_column :accounts, :totp_registered_at, :datetime

    add_column :approval_steps, :meaning, :string
    add_column :approval_steps, :re_auth_at, :datetime
    add_column :approval_steps, :re_auth_factor, :string
    add_column :approval_steps, :signed_c1_digest, :string

    add_column :approval_requests, :ruleset_version, :string
    add_column :approval_requests, :engine_version, :string
    add_column :approval_requests, :disclaimer_version, :string
    add_column :approval_requests, :verdict_snapshot, :jsonb, default: []
  end
end
