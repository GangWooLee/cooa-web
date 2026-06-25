require "test_helper"

class TabHistoryTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers
  setup { Rails.application.load_seed }

  def hero_versions
    comp = Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box")
    comp.component_versions.sort_by(&:version_number)
  end

  test "sanitize: v/s/c만 유지, 레거시 Integer·제외타입(p)·오염 제거 + 세션 정화" do
    s = { open_tabs: [5, "p-1", "v-2", "s-3", "c-4-5", "garbage", nil] }
    keys = TabHistory.sanitize(s)
    assert_equal ["v-2", "s-3", "c-4-5"], keys, "드로어(p)·레거시·오염 제외"
    assert_equal keys, s[:open_tabs], "세션 영구 정화"
  end

  test "track: append-if-absent — 쌓인 순서 유지·재방문 무이동·최근 MAX" do
    s = {}
    TabHistory.track(s, "v", 1)
    TabHistory.track(s, "s", 2)
    TabHistory.track(s, "v", 1) # 재방문 → 무동작(이동 X·중복 X)
    assert_equal ["v-1", "s-2"], s[:open_tabs], "순서 유지, 중복 안 쌓임"
    TabHistory.track(s, "c", "3-4")
    assert_equal ["v-1", "s-2", "c-3-4"], s[:open_tabs], "새 항목은 끝에"
    20.times { |i| TabHistory.track(s, "v", 100 + i) }
    assert_equal TabHistory::MAX, s[:open_tabs].size
    assert_equal "v-119", s[:open_tabs].last, "최신이 끝(오래된 것부터 드롭)"
  end

  test "descriptors: 버전/스크리닝/비교 폴리모픽 + 레거시 섞여도 크래시 없음" do
    from, to = hero_versions.first(2)
    s = { open_tabs: [5, "v-#{from.id}", "s-#{from.id}", "c-#{from.id}-#{to.id}", "v-999999"] }
    ds = TabHistory.descriptors(s).index_by { |d| d[:key] }
    assert_equal component_version_path(from), ds["v-#{from.id}"][:path]
    assert_equal screening_component_version_path(from), ds["s-#{from.id}"][:path]
    assert_equal comparison_path(from_id: from.id, to_id: to.id), ds["c-#{from.id}-#{to.id}"][:path]
    assert_equal from, ds["c-#{from.id}-#{to.id}"][:from]
    assert_equal to, ds["c-#{from.id}-#{to.id}"][:to]
    assert_nil ds["v-999999"], "삭제된 대상 제외(크래시 없음)"
  end
end
