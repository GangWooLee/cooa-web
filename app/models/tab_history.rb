# 헤더 히스토리 탭 — 제품(p)/버전보기(v)/스크리닝(s)을 한 목록으로 관리하는 뷰모델.
# 세션 형태: ["p-1", "v-5", "s-5"] (type-id 키 배열). 레거시 비문자열/오염 키는 무시·정화.
class TabHistory
  include Rails.application.routes.url_helpers

  MAX = 8
  KEY = /\A([a-z])-(\d+)\z/ # type-id (예: "p-1")

  class << self
    # 세션에 키 추가(중복제거·최신순·최대 MAX). 비정상 입력은 세션을 오염시키지 않음.
    def track(session, type, id)
      key = "#{type}-#{id}"
      session[:open_tabs] = sanitize(session).reject { |k| k == key }.unshift(key).first(MAX)
    end

    # 세션 키들 → 탑바 렌더용 디스크립터 배열(삭제/레거시 제외, 순서 보존, 배치 조회)
    def descriptors(session)
      new.descriptors(sanitize(session))
    end

    # 레거시(Integer 등)·오염 키 제거 — 크래시 방지 + 세션 영구 정화
    def sanitize(session)
      keys = (session[:open_tabs] || []).grep(KEY)
      session[:open_tabs] = keys unless keys == session[:open_tabs]
      keys
    end
  end

  # 키 N개를 타입별 2쿼리로 일괄 조회(요청당 N+1 제거)
  def descriptors(keys)
    parsed = keys.filter_map { |k| (m = k.match(KEY)) && [ k, m[1], m[2].to_i ] }
    products = Product.where(id: ids(parsed, "p")).includes(:components).index_by(&:id)
    versions = ComponentVersion.where(id: version_ids(parsed)).includes(component: :product).index_by(&:id)
    parsed.filter_map { |key, type, id| descriptor(key, type, products[id] || versions[id]) }
  end

  private

  def ids(parsed, type) = parsed.filter_map { |_, t, id| id if t == type }
  def version_ids(parsed) = parsed.filter_map { |_, t, id| id unless t == "p" }

  # type별 디스크립터(record 없으면 nil → 호출부 filter_map이 제외)
  def descriptor(key, type, record)
    return unless record

    case type
    when "p"
      { key: key, type: "p", code: record.code, path: product_path(record), frame: "detail", product: record }
    when "v", "s"
      path = type == "v" ? component_version_path(record) : screening_component_version_path(record)
      { key: key, type: type, code: record.product.code, path: path, frame: nil, version: record }
    end
  end
end
