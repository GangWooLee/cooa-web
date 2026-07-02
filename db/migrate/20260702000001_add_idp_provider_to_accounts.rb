# 소셜 로그인 직접 연결(Google) 도입 — idp_subject는 provider별 네임스페이스라 단일 컬럼으론
# Google sub와 Keycloak sub를 구별 못 한다(향후 브로커 도입 시 재바인딩 마이그레이션의 원인).
# provider 차원을 추가해 (tenant, provider, subject)로 유니크를 재구성. 기존 바인딩은 전부
# Keycloak(openid_connect) 경유였으므로 백필.
class AddIdpProviderToAccounts < ActiveRecord::Migration[8.1]
  def up
    add_column :accounts, :idp_provider, :string
    # R4 safety_assured 사유: pre-prod 계정 테이블(수십 행)이라 단문 백필·비동시 인덱스 교체 모두
    # 잠금 부담 없음. prod 규모라면 backfill 분리 + add_index CONCURRENTLY로 전환할 것.
    safety_assured do
      execute "UPDATE accounts SET idp_provider = 'openid_connect' WHERE idp_subject IS NOT NULL"
      remove_index :accounts, name: "index_accounts_on_tenant_id_and_idp_subject"
      add_index :accounts, [ :tenant_id, :idp_provider, :idp_subject ], unique: true,
                where: "idp_subject IS NOT NULL",
                name: "accounts_tenant_provider_subject_key"
    end
  end

  def down
    safety_assured do
      remove_index :accounts, name: "accounts_tenant_provider_subject_key"
      add_index :accounts, [ :tenant_id, :idp_subject ], unique: true,
                where: "idp_subject IS NOT NULL",
                name: "index_accounts_on_tenant_id_and_idp_subject"
    end
    remove_column :accounts, :idp_provider
  end
end
