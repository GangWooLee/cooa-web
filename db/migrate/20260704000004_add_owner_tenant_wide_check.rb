# Stage 2 (adversarial-review m4): owner_must_be_tenant_wide lives only at the model — a validation bypass
# (update_all / raw SQL) could still write a SCOPED owner grant. LastOwnerGuard + EligibleApproverService
# both assume "owner ⇒ tenant-wide", so such a row would silently corrupt those invariants. Add the DB
# CHECK as the hard backstop (mirrors the model rule), same shape as ra_scope_coherence (m1).
class AddOwnerTenantWideCheck < ActiveRecord::Migration[8.1]
  def change
    # R4 safety_assured: role_assignments는 소형 pre-prod 테이블(수십 행). 기존 owner 그랜트는 전부
    # tenant-wide(scope_product_id·scope_component_id 모두 NULL)라 신규 CHECK를 이미 만족 → validate
    # 잠금이 사실상 무부하. add_check_constraint는 자동 역가역(down=remove) → 대칭. (docs/dev-discipline.md R4)
    safety_assured do
      add_check_constraint :role_assignments, <<~SQL.squish, name: "ra_owner_tenant_wide"
        role_key <> 'owner' OR (scope_product_id IS NULL AND scope_component_id IS NULL)
      SQL
    end
  end
end
