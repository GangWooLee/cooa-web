require "test_helper"

# Controller-level authorization enforcement (Pundit strict + deny → 403), distinct from the
# policy-unit matrix (policy_matrix_test) and the SoD demo (demo_flows ④).
class AuthorizationTest < ActionDispatch::IntegrationTest
  def hero_v(n)
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
           .component_versions.find_by(version_number: n)
  end

  def submit_request_for(v)
    post approval_requests_path(component_version_id: v.id) # 김쿠아 리뷰 요청 → pending (버전 앵커, 스크리닝 불요)
    ApprovalRequest.find_by!(component_version_id: v.id)
  end

  # 박쿠아(scm → contributor)는 리뷰어(approver) 역할이 없어 검토 확인 거부 — SoD 이전에 역할에서 차단.
  test "a contributor cannot confirm a review (role deny, distinct from SoD)" do
    req = submit_request_for(hero_v(5))
    sign_in_as(Account.find_by!(email: "park@cooa.dev")) # scm → contributor (리뷰어 아님)
    post confirm_approval_request_path(req)
    assert_response :forbidden
    assert_equal "pending", req.reload.status, "역할 없는 사용자의 검토 확인은 거부되어야 함"
  end

  # Phase 3a: a Pundit denial is persisted to the append-only audit log (deny spikes = BOLA signal).
  test "a denied action is recorded in the audit log" do
    req = submit_request_for(hero_v(5))
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    assert_difference -> { AuditLog.where(outcome: "deny").count }, 1 do
      post confirm_approval_request_path(req)
    end
    # H1 leak-immunity: identify THE deny this test provoked, not "the newest deny in the whole table".
    # The old unscoped `AuditLog.where(outcome: "deny").order(:tenant_seq).last` picked whichever deny had
    # the global-max tenant_seq — so a COMMITTED probe deny leaked from another tenant (rls_app_connection_test
    # writes tenant=@org_a, action='probe', outcome='deny') could win and flip log.action to 'probe' (the
    # intermittent flake). Scoping to THIS tenant + THIS action makes the query immune by construction.
    demo = TenantConfig::DEMO_TENANT_ID
    # Proof-in-place: plant exactly such a foreign-tenant deny row and prove the scoped query still ignores
    # it. Seq = GLOBAL max + 1 (NOT 1): the demo confirm_review deny sits at seq 2, so only a strictly larger
    # seq lands at the tail of the OLD `.order(:tenant_seq).last` — the worst case the scope must survive
    # (this is what the F5 revert experiment exploits to turn the old query RED). Owner bypasses RLS for the
    # insert; a SAVEPOINT we roll back is the ONLY cleanup, since audit_logs' immutable trigger blocks DELETE.
    AuditLog.transaction(requires_new: true) do
      poison_seq = AuditLog.maximum(:tenant_seq).to_i + 1
      AuditLog.connection.execute(<<~SQL)
        INSERT INTO audit_logs (tenant_id, action, resource_type, outcome, tenant_seq, chain_hash)
        VALUES ('99999999-9999-9999-9999-999999999999', 'probe', 'X', 'deny', #{poison_seq}, 'h')
      SQL
      log = AuditLog.where(tenant_id: demo, action: "confirm_review", outcome: "deny").order(:tenant_seq).last
      assert_equal "confirm_review", log.action, "scoped query must ignore the leaked foreign-tenant probe deny"
      assert_equal "ApprovalRequest", log.resource_type
      raise ActiveRecord::Rollback # discard the planted probe (cannot DELETE — immutable trigger)
    end
  end
end
