# Append-only audit-log chain verification + BOLA detection (Phase 3a, ADR-002 §5.4).
# Run as the OWNER (COOA_DB_USER) so it can walk every tenant's chain (RLS bypass for the auditor).
namespace :audit do
  desc "Verify each tenant's hash chain: recompute hashes, detect tamper + sequence gaps"
  task verify: :environment do
    tenant_ids = ActiveRecord::Base.connection.select_values("SELECT DISTINCT tenant_id FROM audit_logs")
    total = 0
    bad = []
    tenant_ids.each do |tid|
      prev = nil
      expected_seq = 0
      AuditLog.where(tenant_id: tid).order(:tenant_seq).each do |row|
        expected_seq += 1
        bad << "tenant #{tid} seq=#{row.tenant_seq}: gap (expected #{expected_seq})" if row.tenant_seq != expected_seq
        bad << "tenant #{tid} seq=#{row.tenant_seq}: prev_chain_hash broken" if row.prev_chain_hash != prev&.chain_hash
        bad << "tenant #{tid} seq=#{row.tenant_seq}: chain_hash tampered" if row.chain_hash != row.expected_chain_hash
        prev = row
        total += 1
      end
    end
    abort "audit:verify FAILED (#{bad.size}):\n#{bad.first(20).join("\n")}" if bad.any?
    puts "audit:verify OK — #{total} row(s) across #{tenant_ids.size} tenant(s); chains intact."
  end

  desc "Flag actors with deny bursts (BOLA probe). Env: MINUTES (default 5), THRESHOLD (default 10)"
  task detect_bola: :environment do
    minutes = Integer(ENV.fetch("MINUTES", 5))
    threshold = Integer(ENV.fetch("THRESHOLD", 10))
    hot = AuditLog.where(outcome: "deny").where("ts > ?", minutes.minutes.ago)
                  .group(:tenant_id, :actor_id).count.select { |_, c| c >= threshold }
    if hot.any?
      hot.each { |(tid, aid), c| puts "BOLA? tenant=#{tid} actor=#{aid} denies=#{c} (>= #{threshold} in #{minutes}m)" }
      abort "detect_bola: #{hot.size} actor(s) over threshold"
    end
    puts "detect_bola OK — no actor exceeded #{threshold} denies in #{minutes}m."
  end
end
