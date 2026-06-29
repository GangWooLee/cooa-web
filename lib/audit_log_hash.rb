# Deterministic canonical serialization + SHA256 chaining for the append-only audit log (Phase 3a).
# Determinism is load-bearing: audit:verify recomputes each row's hash, so the same row must ALWAYS
# serialize identically — stable key order, recursively-sorted jsonb, fixed scalar stringification.
module AuditLogHash
  module_function

  # fields: Hash (symbol keys) of the chained columns (exclude id / chain_hash / prev_chain_hash).
  def canonical(fields)
    fields.sort_by { |k, _| k.to_s }.map { |k, v| "#{k}=#{serialize(v)}" }.join("\n")
  end

  def compute(canonical_body, prev_chain_hash)
    Digest::SHA256.hexdigest("#{prev_chain_hash}\n#{canonical_body}")
  end

  def serialize(value)
    case value
    when nil then ""
    when Hash, Array then JSON.generate(deep_sort(value))
    else value.to_s
    end
  end

  # Recursively stringify+sort hash keys so {a:1,b:2} and {"b"=>2,"a"=>1} (jsonb round-trip) match.
  def deep_sort(obj)
    case obj
    when Hash then obj.keys.sort_by(&:to_s).each_with_object({}) { |k, h| h[k.to_s] = deep_sort(obj[k]) }
    when Array then obj.map { |e| deep_sort(e) }
    else obj
    end
  end
end
