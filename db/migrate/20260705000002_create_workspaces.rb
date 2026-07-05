# WS-track (D1 m-a): 작업실(Workspace) = 복수 루트 제품을 담는 상위 컨테이너. 지금까지 "루트=작업실 1:1"
# 가정으로 굴러갔으나, 하나의 작업실에 여러 루트 트리를 담을 수 있게 실체 테이블로 승격한다. 기존 테넌트
# 테이블 관례(tenant_id uuid NOT NULL · UNIQUE(tenant_id,id) 복합 FK 앵커 · ENABLE+FORCE RLS + tenant_isolation
# policy)를 그대로 따른다. R8: cooa.rake RLS_TABLES + committed_state_cleanup.rb 상수 + rls:grant_app.
require Rails.root.join("lib/tenant_rls")

class CreateWorkspaces < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    create_table :workspaces do |t|
      t.uuid :tenant_id, null: false
      t.string :name, null: false
      t.integer :position, default: 0
      t.timestamps
      t.index :tenant_id
    end
    # R4 safety_assured: 방금 만든 빈 테이블에 대한 제약/정책이라 잠금·검증 무부하. strong_migrations는 raw
    # execute 내부를 검사하지 못해 무조건 막으므로 명시적으로 안전을 보증한다. (docs/dev-discipline.md R4)
    safety_assured do
      # 복합 FK 앵커(products_tenant_id_id_key 선례) — products.workspace_id가 (tenant_id,id)로 참조.
      execute "ALTER TABLE workspaces ADD CONSTRAINT workspaces_tenant_id_id_key UNIQUE (tenant_id, id)"
      # 같은 테넌트 격리 정책(NULLIF → fail-CLOSED) + cooa_app DML grant(structure.sql가 GRANT 스트립 → 재적용은 cooa.rake).
      enable_tenant_rls! "workspaces"
    end
  end

  def down
    disable_tenant_rls! "workspaces"
    drop_table :workspaces
  end
end
