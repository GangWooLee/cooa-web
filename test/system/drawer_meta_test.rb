require "application_system_test_case"

# 드로어 메타 — 커스텀 속성(Notion식) + 자유 역할 담당자(동적 행)
class DrawerMetaTest < ApplicationSystemTestCase

  def leaf = Product.find_by(code: "CO0001")

  # 드로어 진입 + Stimulus 연결 정착(무거운 대시보드 뒤 드로어라 연결이 느릴 수 있음)
  def visit_drawer(product)
    page.current_window.resize_to(1440, 900)
    visit product_path(product)
    assert_selector "#detail", wait: 10
    sleep 0.3
  end

  # 인라인 편집 열기 재시도 — 클릭이 Stimulus 연결 전에 발생하는 레이스 대비
  def open_editor(input_css)
    3.times do
      yield.click
      return if has_css?(input_css, wait: 3)
    end
    assert_selector input_css
  end

  def js_click(css)
    find(css, visible: :all).execute_script("this.click()")
  end

  test "커스텀 속성 추가 → 키 이름변경 → 값 편집" do
    l = leaf
    before = l.product_properties.count
    visit_drawer(l)

    # 속성 추가 → 새 키 입력 auto-focus
    within("#detail") { click_button "속성 추가" }
    inp = find("#detail input[id^='prop_name_']", wait: 12) # 생성 직후 키 인라인(보이는 유일)
    prop = ProductProperty.find(inp[:id][/\d+/])
    assert_equal before + 1, l.product_properties.count
    assert_equal "속성", prop.name, "기본 키명"

    # 키 이름변경
    fill_in inp[:id], with: "성분"
    find("##{inp[:id]}").send_keys(:enter)
    assert_selector "#detail dt", text: "성분", wait: 12
    assert_equal "성분", prop.reload.name

    # 값 편집 (None → 입력) — 새 속성만 값이 None
    open_editor("#prop_value_#{prop.id}") { find("#detail dd[data-controller='inline-edit'] span", exact_text: "None", wait: 12) }
    fill_in "prop_value_#{prop.id}", with: "히알루론산"
    find("#prop_value_#{prop.id}").send_keys(:enter)
    assert_text "히알루론산", wait: 12
    assert_equal "히알루론산", prop.reload.value
  end

  test "커스텀 속성 삭제(호버 휴지통)" do
    l = leaf
    prop = l.product_properties.create!(name: "삭제대상", value: "x", position: 9)
    visit_drawer(l)
    assert_selector "#detail dt", text: "삭제대상"
    accept_confirm { js_click("#detail form[action='#{product_product_property_path(l, prop)}'] button") }
    assert_no_selector "#detail dt", text: "삭제대상", wait: 5
    assert_not ProductProperty.exists?(prop.id)
  end

  test "담당자 추가(자유 역할 + 팀에서 선택) → 저장" do
    l = leaf
    song = User.find_by(name: "송쿠아")
    visit_drawer(l)

    open_editor("#detail [data-members-target='row']") { find("#detail dd[data-controller~='members'] span[data-inline-edit-target='display']") }
    within("#detail") { click_button "담당자 추가" }
    row = all("#detail [data-members-target='row']").last
    within(row) do
      find("input[name='members[][role]']").set("마케팅")
      find("select").find(:option, text: "송쿠아").select_option
    end
    within("#detail") { click_button "저장" }

    assert_selector "#detail", text: "마케팅", wait: 10
    assert_equal song, l.reload.member_for("마케팅")
  end

  test "담당자 행 삭제(x) → 저장 시 wipe" do
    l = leaf
    n = l.product_members.count
    assert n.positive?
    visit_drawer(l)
    open_editor("#detail [data-members-target='row']") { find("#detail dd[data-controller~='members'] span[data-inline-edit-target='display']") }
    assert_selector "#detail [data-members-target='row']", count: n # 폼 열림 = n행
    # 첫 행 삭제 — 작은 아이콘 버튼은 좌표클릭이 불안정 → JS 클릭
    page.execute_script("document.querySelector(\"#detail [data-members-target='row'] [data-action*='members#remove']\").click()")
    assert_selector "#detail [data-members-target='row']", count: n - 1, wait: 5 # DOM에서 1행 제거 확인
    within("#detail") { click_button "저장" }
    assert_no_selector "#detail input[name='members[][role]']", wait: 10 # 저장 후 풀 리렌더(폼 숨김) 대기
    assert_equal n - 1, l.reload.product_members.count, "삭제된 행은 저장 시 제거"
  end

  test "무변경 인라인 클릭은 저장·리렌더 없음(깜빡임 방지)" do
    l = leaf
    visit_drawer(l)
    within("#detail") do
      open_editor("#product_channel") { find("dd[data-controller='inline-edit'] span", exact_text: "QTEN") } # 채널 편집 열기
      find("dd[data-controller='inline-edit'] span", exact_text: "CO0001").click # 변경 없이 품목코드로 이동
    end
    # 채널은 no-op으로 닫히고(미저장), 품목코드는 편집모드 유지 = 풀 리렌더 없었음
    assert_selector "#detail #product_code", visible: true, wait: 10
    assert_equal "QTEN", l.reload.channel, "무변경 → 저장(PATCH) 안 됨"
  end
end
