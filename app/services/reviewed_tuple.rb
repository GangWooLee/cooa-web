# 리뷰 스냅샷(리프레임): 리뷰어가 검토하는 시점의 버전 콘텐츠를 캡처 — submit(리뷰 요청) 시 저장,
# confirm(검토 확인) 시 재비교. 결정적 직렬화(안정 정렬)라 리뷰 요청 이후 콘텐츠/아트워크가 바뀌면 감지된다
# (TOCTOU 경량 가드: 리뷰어가 보지 않은 내용을 확인하는 것을 막음). 규제 전자서명·verdict 스냅샷은 폐지.
module ReviewedTuple
  module_function

  def capture(component_version)
    {
      reviewed_artifact_digest: artifact_digest(component_version),
      reviewed_content_snapshot_hash: content_snapshot_hash(component_version)
    }
  end

  # 리뷰 요청 이후 버전 콘텐츠/아트워크가 바뀌었으면 확인 차단(요청은 pending 유지; 재검토 후 재요청).
  def stale?(approval_request)
    cv = approval_request.component_version
    content_snapshot_hash(cv) != approval_request.reviewed_content_snapshot_hash ||
      artifact_digest(cv) != approval_request.reviewed_artifact_digest
  end

  # label_texts (text_type,language,country,id) + ingredients (position,id) — 결정적; 문자열 포맷은
  # 안정적이기만 하면 됨(해시 입력일 뿐 표시 안 함).
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
end
