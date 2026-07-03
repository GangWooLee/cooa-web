require Rails.root.join("lib/tenant_rls").to_s

# 리뷰 재앵커: approval_request를 screening_run → component_version에. 사용자 워크플로 교정 반영 —
# AI 사전심사는 RA/담당자가 수행하므로 디자이너는 스크리닝 없이 리뷰를 요청해야 함 → 리뷰는 스크리닝이
# 아니라 "버전"에 붙는다. 기존 행은 run→cv로 backfill. UNIQUE·composite FK를 cv 기준으로 교체.
# owner 실행(COOA_DB_USER).
class ReanchorApprovalToVersion < ActiveRecord::Migration[8.1]
  include TenantRls

  def up
    add_column :approval_requests, :component_version_id, :bigint
    execute <<~SQL
      UPDATE approval_requests ar
      SET component_version_id = sr.component_version_id
      FROM screening_runs sr
      WHERE sr.id = ar.screening_run_id
    SQL
    change_column_null :approval_requests, :component_version_id, false

    # 구 screening_run 앵커 제거(composite FK는 raw SQL로 생성됐으므로 raw drop)
    execute "ALTER TABLE approval_requests DROP CONSTRAINT approval_requests_run_tenant_fkey"
    remove_index :approval_requests, name: "index_approval_requests_on_tenant_id_and_screening_run_id"
    remove_column :approval_requests, :screening_run_id

    # 신 component_version 앵커
    add_index :approval_requests, [ :tenant_id, :component_version_id ], unique: true,
              name: "index_approval_requests_on_tenant_id_and_component_version_id"
    composite_fk!(:approval_requests, :component_version_id, :component_versions, name: "approval_requests_cv_tenant_fkey")
  end

  def down
    add_column :approval_requests, :screening_run_id, :bigint # best-effort(다중 run은 최신으로)
    execute <<~SQL
      UPDATE approval_requests ar
      SET screening_run_id = (
        SELECT sr.id FROM screening_runs sr
        WHERE sr.component_version_id = ar.component_version_id
        ORDER BY sr.created_at DESC, sr.id DESC LIMIT 1
      )
    SQL
    execute "ALTER TABLE approval_requests DROP CONSTRAINT approval_requests_cv_tenant_fkey"
    remove_index :approval_requests, name: "index_approval_requests_on_tenant_id_and_component_version_id"
    remove_column :approval_requests, :component_version_id
    add_index :approval_requests, [ :tenant_id, :screening_run_id ], unique: true,
              name: "index_approval_requests_on_tenant_id_and_screening_run_id"
    composite_fk!(:approval_requests, :screening_run_id, :screening_runs, name: "approval_requests_run_tenant_fkey")
  end
end
