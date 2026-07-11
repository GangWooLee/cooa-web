# 헤더 히스토리 탭 — 풀페이지 작업(버전 보기 v / 비교 c / 스크리닝 s)만 기록하는 뷰모델.
#   · 드로어(제품) 진입은 기록하지 않음.
#   · 쌓인 순서 유지(append-if-absent): 중복은 무동작·이동 없음, 새 항목만 끝에 추가, 최근 MAX 유지.
# 세션 형태: ["v-5", "s-5", "c-5-6"] (type-id 키). 레거시 비문자열/제외타입(p)/오염 키는 무시·정화.
class TabHistory
  include Rails.application.routes.url_helpers

  MAX = 12
  KEY = /\A([svc])-([\d-]+)\z/ # v-{id} / s-{id} / c-{from}-{to}

  class << self
    # 쌓인 순서 유지하며 추가(중복이면 무동작) → 최근 MAX
    def track(session, type, id)
      key = "#{type}-#{id}"
      tabs = sanitize(session)
      tabs << key unless tabs.include?(key)
      session[:open_tabs] = tabs.last(MAX)
    end

    # 세션 키들 → 탑바 렌더용 디스크립터(삭제/제외/레거시 제외, 순서 보존, 배치 조회)
    def descriptors(session)
      new.descriptors(sanitize(session))
    end

    # 유효 키(v/s/c)만 남김 — 레거시 Integer·제외타입(p)·오염 제거 + 세션 영구 정화
    def sanitize(session)
      keys = (session[:open_tabs] || []).grep(KEY)
      session[:open_tabs] = keys unless keys == session[:open_tabs]
      keys
    end
  end

  # 키 N개를 ComponentVersion 1쿼리로 일괄 조회(요청당 N+1 제거)
  def descriptors(keys)
    parsed = keys.filter_map { |k| (m = k.match(KEY)) && [ k, m[1], m[2] ] } # [key, type, rest]
    vids = parsed.flat_map { |_, type, rest| type == "c" ? rest.split("-") : [ rest ] }.map(&:to_i).uniq
    versions = ComponentVersion.where(id: vids).includes(component: :product).index_by(&:id)
    parsed.filter_map { |key, type, rest| descriptor(key, type, rest, versions) }
  end

  private

  # type별 디스크립터(대상 없으면 nil → 호출부 filter_map이 제외)
  def descriptor(key, type, rest, versions)
    case type
    when "v", "s"
      v = versions[rest.to_i] or return
      path = type == "v" ? component_version_path(v) : screening_component_version_path(v)
      { key: key, type: type, code: v.product.code, path: path, frame: nil, version: v }
    when "c"
      fid, tid = rest.split("-", 2).map(&:to_i)
      from = versions[fid]
      to = versions[tid]
      return unless from && to
      { key: key, type: "c", code: from.product.code, path: comparison_path(from_id: fid, to_id: tid),
        frame: nil, from: from, to: to }
    end
  end
end
