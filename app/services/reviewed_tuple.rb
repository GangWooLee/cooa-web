# C1 reviewed-tuple (ADR-002 §5.3): the artifacts the RA actually reviewed — captured at submit_for_approval,
# re-validated at approve. Deterministic serialization (stable ordering) so any edit to the content,
# artwork, verdict, or engine versions SINCE submit is detectable. Defends the text-over-artwork swap:
# the artwork digest and the (separately-editable) label_texts+ingredients content are hashed apart.
module ReviewedTuple
  module_function

  def capture(screening_run)
    cv = screening_run.component_version
    {
      reviewed_artifact_digest: artifact_digest(cv),
      reviewed_content_snapshot_hash: content_snapshot_hash(cv),
      ruleset_version: ScreeningService::RULESET_VERSION,
      engine_version: ScreeningService::ENGINE_VERSION,
      disclaimer_version: ScreeningService::DISCLAIMER_VERSION,
      verdict_snapshot: verdict_snapshot(screening_run)
    }
  end

  # Approving a stale tuple would sign something the RA did not review → block (request stays pending;
  # re-screen + re-submit). Compares the LIVE artifacts to what was captured at submit.
  def stale?(approval_request)
    run = approval_request.screening_run
    cv = run.component_version
    content_snapshot_hash(cv) != approval_request.reviewed_content_snapshot_hash ||
      artifact_digest(cv) != approval_request.reviewed_artifact_digest ||
      verdict_snapshot(run) != approval_request.verdict_snapshot ||
      ScreeningService::RULESET_VERSION != approval_request.ruleset_version ||
      ScreeningService::ENGINE_VERSION != approval_request.engine_version ||
      ScreeningService::DISCLAIMER_VERSION != approval_request.disclaimer_version # P2 review: captured but was not re-checked
  end

  # label_texts (text_type,language,country,id) + ingredients (position,id) — deterministic; the string
  # format need only be stable (it is a hash input, never displayed).
  def content_snapshot_hash(component_version)
    parts = component_version.label_texts.order(:text_type, :language, :country, :id)
                             .map { |lt| "LT:#{lt.text_type}:#{lt.language}:#{lt.country}:#{lt.content}" }
    parts += component_version.ingredients.order(:position, :id)
                              .map { |i| "ING:#{i.inci_canonical}:#{i.inci_name}:#{i.declared_pct}:#{i.position}" }
    Digest::SHA256.hexdigest(parts.join("||"))
  end

  def artifact_digest(component_version)
    raw = component_version.artwork.attached? ? component_version.artwork.blob.checksum.to_s : component_version.image_name.to_s
    Digest::SHA256.hexdigest(raw)
  end

  def verdict_snapshot(screening_run)
    screening_run.screening_findings.order(:position, :id).map do |f|
      { "finding_id" => f.id, "decision" => f.decision, "element_type" => f.element_type, "subject" => f.subject }
    end
  end
end
