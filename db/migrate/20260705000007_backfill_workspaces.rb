# WS-track (D1 m-f): 기존 세계("루트=작업실 1:1")를 새 스키마로 이관한다.
#  (1) 기존 루트 제품마다 동명 workspace 생성(테넌트·이름·position 승계) + products.workspace_id 백필(루트만).
#  (2) 루트 대상 product-scope brand_admin grant → workspace-scope 이관(jung@비타민C 해당). 리프 대상
#      product-scope(choi@CO0200[external])는 불변 — 루트가 아니라서 매칭 안 됨.
#  (3) invitations 미러(루트 대상 스코프 초대가 있으면 대칭 이관 — 시드엔 없지만 대칭 보장).
# 가드: 백필 후 workspace_id 없는 루트가 남으면 abort. down은 대칭(workspace-scope → 루트 product-scope 역이관
# → products.workspace_id NULL → workspaces 삭제).
class BackfillWorkspaces < ActiveRecord::Migration[8.1]
  # R4 safety_assured: 전부 데이터 백필(execute UPDATE/INSERT)이라 strong_migrations의 DDL 안전검사 대상이
  # 아니지만, raw execute 내부를 검사 못 해 무조건 막으므로 명시 보증. 소형 pre-prod 테이블. (R4)
  def up
    safety_assured { backfill_up }
  end

  def down
    safety_assured { backfill_down }
  end

  private

  def backfill_up
    roots = select_all(
      "SELECT id, tenant_id, name, COALESCE(position, 0) AS position FROM products WHERE parent_id IS NULL ORDER BY id"
    ).to_a
    roots.each do |r|
      ws_id = select_value(<<~SQL)
        INSERT INTO workspaces (tenant_id, name, position, created_at, updated_at)
        VALUES (#{quote(r['tenant_id'])}, #{quote(r['name'])}, #{r['position'].to_i}, now(), now())
        RETURNING id
      SQL
      execute "UPDATE products SET workspace_id = #{ws_id.to_i} WHERE id = #{r['id'].to_i}"
    end

    orphan = select_value("SELECT COUNT(*) FROM products WHERE parent_id IS NULL AND workspace_id IS NULL").to_i
    raise "backfill_workspaces: #{orphan} root product(s) still missing workspace_id — aborting" if orphan.positive?

    # 루트 대상 product-scope brand_admin grant → workspace-scope(그 루트의 workspace).
    execute <<~SQL
      UPDATE role_assignments ra
         SET scope_type = 'workspace', scope_workspace_id = p.workspace_id, scope_product_id = NULL
        FROM products p
       WHERE ra.scope_product_id = p.id
         AND p.parent_id IS NULL
         AND ra.role_key = 'brand_admin'
         AND ra.scope_type = 'product'
    SQL

    # invitations 미러(루트 대상 스코프 초대 대칭 이관).
    execute <<~SQL
      UPDATE invitations inv
         SET scope_type = 'workspace', scope_workspace_id = p.workspace_id, scope_product_id = NULL
        FROM products p
       WHERE inv.scope_product_id = p.id
         AND p.parent_id IS NULL
         AND inv.scope_type = 'product'
    SQL
  end

  def backfill_down
    # workspace-scope grant/invite → 그 작업실의 루트 product-scope로 역이관(1:1 백필이라 루트 정확히 1개).
    execute <<~SQL
      UPDATE role_assignments ra
         SET scope_type = 'product',
             scope_product_id = (SELECT id FROM products WHERE workspace_id = ra.scope_workspace_id AND parent_id IS NULL ORDER BY id LIMIT 1),
             scope_workspace_id = NULL
       WHERE ra.scope_type = 'workspace'
    SQL
    execute <<~SQL
      UPDATE invitations inv
         SET scope_type = 'product',
             scope_product_id = (SELECT id FROM products WHERE workspace_id = inv.scope_workspace_id AND parent_id IS NULL ORDER BY id LIMIT 1),
             scope_workspace_id = NULL
       WHERE inv.scope_type = 'workspace'
    SQL
    execute "UPDATE products SET workspace_id = NULL WHERE parent_id IS NULL"
    execute "DELETE FROM workspaces"
  end
end
