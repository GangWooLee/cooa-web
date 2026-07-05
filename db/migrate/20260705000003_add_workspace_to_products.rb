# WS-track (D1 m-b): products.workspace_id — 루트 제품이 자기 작업실을 가리킨다(자식은 NULL, brand_root로 도출).
# 복합 FK (tenant_id, workspace_id) → workspaces (tenant_id, id) 로 교차테넌트 참조를 원천 차단(관례). ON DELETE
# RESTRICT — 제품이 매달린 작업실은 지워질 수 없다(작업실 삭제는 트리 이전/정리 선행). 인덱스로 workspace→루트 조회.
class AddWorkspaceToProducts < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :workspace_id, :bigint

    # R4 safety_assured: products.workspace_id는 방금 추가된 컬럼 → 전 행 NULL. FK 검증이 스캔할 non-null 참조
    # 0건 · 인덱스도 소형 pre-prod 테이블(수십 행)이라 비동시 생성 잠금이 사실상 무부하. (docs/dev-discipline.md R4)
    safety_assured do
      execute <<~SQL
        ALTER TABLE products
          ADD CONSTRAINT fk_products_workspace
          FOREIGN KEY (tenant_id, workspace_id) REFERENCES workspaces (tenant_id, id) ON DELETE RESTRICT
      SQL
      add_index :products, :workspace_id
    end
  end

  def down
    remove_index :products, :workspace_id
    execute "ALTER TABLE products DROP CONSTRAINT IF EXISTS fk_products_workspace"
    remove_column :products, :workspace_id
  end
end
