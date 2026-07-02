require Rails.root.join("lib/tenant_rls").to_s

# 조직 초대(Figma식 멤버십 티켓) — Phase 3. 토큰은 SHA-256 digest만 저장(원문은 생성 응답 1회 노출),
# 상태는 컬럼 대신 타임스탬프 3종(accepted/revoked/expires)에서 파생 — 상태 드리프트 없음.
# 수락 = 로그인 콜백의 invitation-gated 계정 생성(sessions#accept_invitation_signup).
class CreateInvitations < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    create_table :invitations, id: :uuid do |t|
      t.uuid     :tenant_id, null: false
      t.string   :email, null: false                  # 저장 시 downcase(모델 normalizes)
      t.string   :role_key, null: false               # INVITABLE(owner 제외 — 권한 상승 차단) 모델 검증
      t.string   :token_digest, null: false           # SHA-256(raw) — 원문 미저장
      t.uuid     :invited_by_account_id, null: false  # FK 없는 uuid — role_assignments.granted_by 선례
      t.uuid     :accepted_account_id                 # 수락 시 생성된 Account
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :invitations, :token_digest, unique: true
    # 테넌트당 이메일 1개의 "오픈" 초대만 — 만료는 predicate에 못 넣으므로(now() 비불변)
    # 만료 초대 재발급은 revoke+신규 생성으로 처리(유니크 충돌 회피).
    add_index :invitations, [ :tenant_id, :email ], unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL",
              name: "invitations_tenant_open_email_key"
    add_index :invitations, [ :tenant_id, :created_at ], name: "invitations_tenant_list_idx"
    # R4 safety_assured 사유: 방금 만든 빈 테이블 — FK 검증 잠금·RLS raw execute 모두 무부하.
    safety_assured do
      add_foreign_key :invitations, :organizations, column: :tenant_id
      enable_tenant_rls!("invitations")
    end
  end

  def down = drop_table(:invitations)
end
