require "test_helper"

# Append-only hash-chained audit log (Phase 3a, ADR-002 §5.4). Owner connection (RLS bypassed) — these
# verify the chain logic + DB immutability; RLS isolation/grants are covered by rls:audit + the RLS suite.
class AuditLogTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "감사자", role: "ra", avatar_color: "#222222", email: "auditor@test")
    @account = Account.create!(tenant_id: Current.tenant_id, user: @user, email: "auditor@test", status: "active")
    Current.account = @account
  end

  test "record! builds a linked, verifiable per-tenant chain" do
    a = AuditLog.record!(action: "approve", resource_type: "ScreeningRun", resource_id: 1, outcome: "allow", after: { b: 2, a: 1 })
    b = AuditLog.record!(action: "reject", resource_type: "ScreeningRun", resource_id: 2, outcome: "allow")
    assert_equal [1, 2], [a.tenant_seq, b.tenant_seq]
    assert_nil a.prev_chain_hash
    assert_equal a.chain_hash, b.prev_chain_hash, "chain links seq n→n+1"
    assert_equal a.chain_hash, a.expected_chain_hash
    assert_equal b.chain_hash, b.expected_chain_hash
    assert_equal @user.id, a.actor_id, "actor = linked domain user (bigint)"
    assert_equal @account.id, a.actor_account_id
    assert_equal "JP", a.region
  end

  test "record! stamps the current policy_version (P2 M-3)" do
    a = AuditLog.record!(action: "approve", resource_type: "X", resource_id: 1, outcome: "allow")
    assert_equal Authz::PermissionMatrix::MATRIX_VERSION, a.policy_version
    refute_equal 0, a.policy_version, "policy_version must not be the unstamped default"
  end

  test "allow requires a domain actor (fail-CLOSED for unlinked accounts)" do
    Current.account = nil
    assert_raises(RuntimeError) { AuditLog.record!(action: "x", resource_type: "Y", outcome: "allow") }
  end

  test "deny may have a nil actor (recording the probe is the point)" do
    Current.account = nil
    d = AuditLog.record!(action: "run_screening", resource_type: "ComponentVersion", outcome: "deny", denial_reason: "pundit")
    assert_nil d.actor_id
    assert_equal "deny", d.outcome
    assert_equal 1, d.tenant_seq
  end

  test "tampering is detectable — recompute diverges from the stored chain_hash" do
    a = AuditLog.record!(action: "approve", resource_type: "X", resource_id: 1, outcome: "allow")
    assert_equal a.chain_hash, a.expected_chain_hash
    a.after = { "evil" => true } # mutate a chained field in memory
    refute_equal a.chain_hash, a.expected_chain_hash
  end

  test "the immutability trigger blocks UPDATE (even the owner)" do
    a = AuditLog.record!(action: "approve", resource_type: "X", resource_id: 1, outcome: "allow")
    assert_raises(ActiveRecord::StatementInvalid) { a.update_column(:outcome, "deny") }
  end

  test "the immutability trigger blocks DELETE (even the owner)" do
    a = AuditLog.record!(action: "approve", resource_type: "X", resource_id: 1, outcome: "allow")
    assert_raises(ActiveRecord::StatementInvalid) { AuditLog.where(id: a.id).delete_all }
  end

  test "UNIQUE(tenant_id, tenant_seq) backstops the chain against a duplicate sequence" do
    AuditLog.record!(action: "approve", resource_type: "X", resource_id: 1, outcome: "allow") # seq 1
    assert_raises(ActiveRecord::RecordNotUnique) do
      AuditLog.connection.execute(<<~SQL)
        INSERT INTO audit_logs (tenant_id, tenant_seq, action, resource_type, outcome, chain_hash)
        VALUES ('#{Current.tenant_id}', 1, 'dup', 'X', 'deny', 'h')
      SQL
    end
  end
end
