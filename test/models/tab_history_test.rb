require "test_helper"

class TabHistoryTest < ActiveSupport::TestCase
  setup { Rails.application.load_seed }

  test "sanitize: 레거시 Integer/오염 키 제거 + 세션 정화" do
    s = { open_tabs: [5, "p-1", "v-2", "garbage", nil, "x-9"] }
    keys = TabHistory.sanitize(s)
    assert_equal ["p-1", "v-2", "x-9"], keys, "type-id 형식만 유지(x-9는 형식 OK·렌더 시 미지타입 제외)"
    assert_equal keys, s[:open_tabs], "세션도 영구 정화"
  end

  test "descriptors: 레거시 Integer가 섞여도 크래시 없이 유효 탭만(회귀)" do
    p = Product.find_by(code: "CO0001")
    s = { open_tabs: [p.id, "p-#{p.id}", "v-999999"] } # Integer 레거시 + 유효 + 삭제된 대상
    descs = TabHistory.descriptors(s)
    assert_equal ["p-#{p.id}"], descs.map { |d| d[:key] }, "레거시·삭제 제외, 유효만"
    assert_equal p.code, descs.first[:code]
    assert_equal "detail", descs.first[:frame]
  end

  test "descriptors: 제품/버전/스크리닝 폴리모픽 디스크립터" do
    p = Product.find_by(code: "CO0001")
    v = p.components.first.component_versions.first
    s = { open_tabs: ["p-#{p.id}", "v-#{v.id}", "s-#{v.id}"] }
    by_type = TabHistory.descriptors(s).index_by { |d| d[:type] }
    assert_equal screening_component_version_path(v), by_type["s"][:path]
    assert_equal component_version_path(v), by_type["v"][:path]
    assert_equal v, by_type["v"][:version]
  end

  test "track: 중복제거·최신순·최대 8" do
    s = {}
    TabHistory.track(s, "p", 1)
    TabHistory.track(s, "v", 2)
    TabHistory.track(s, "p", 1) # 재방문 → 맨 앞
    assert_equal ["p-1", "v-2"], s[:open_tabs]
    12.times { |i| TabHistory.track(s, "p", 100 + i) }
    assert_equal TabHistory::MAX, s[:open_tabs].size, "최대 MAX개"
  end

  # url 헬퍼 사용을 위해 통합 테스트 컨텍스트
  include Rails.application.routes.url_helpers
end
