require "application_system_test_case"

# 드로어 메타 — 커스텀 속성(Notion식) + 자유 역할 담당자(동적 행)
class DrawerMetaTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  def leaf = Product.find_by(code: "CO0001")

  test "커스텀 속성 추가 → 키 이름변경 → 값 편집" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    l = leaf
    before = l.product_properties.count
    visit product_path(l)

    # 속성 추가 → 새 키 입력 auto-focus
    within("#detail") { click_button "속성 추가" }
    inp = find("#detail input[id^='prop_name_']", wait: 5) # 생성 직후 키 인라인(보이는 유일)
    prop = ProductProperty.find(inp[:id][/\d+/])
    assert_equal before + 1, l.product_properties.count
    assert_equal "속성", prop.name, "기본 키명"

    # 키 이름변경
    fill_in inp[:id], with: "성분"
    find("##{inp[:id]}").send_keys(:enter)
    assert_selector "#detail dt", text: "성분", wait: 5
    assert_equal "성분", prop.reload.name

    # 값 편집 (None → 입력) — 새 속성만 값이 None
    within("#detail") { find("dd[data-controller='inline-edit'] span", exact_text: "None").click }
    fill_in "prop_value_#{prop.id}", with: "히알루론산"
    find("#prop_value_#{prop.id}").send_keys(:enter)
    assert_text "히알루론산", wait: 5
    assert_equal "히알루론산", prop.reload.value
  end

  test "커스텀 속성 삭제(호버 휴지통)" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    l = leaf
    prop = l.product_properties.create!(name: "삭제대상", value: "x", position: 9)
    visit product_path(l)
    assert_selector "#detail dt", text: "삭제대상"
    accept_confirm { js_click("#detail form[action='#{product_product_property_path(l, prop)}'] button") }
    assert_no_selector "#detail dt", text: "삭제대상", wait: 5
    assert_not ProductProperty.exists?(prop.id)
  end

  test "담당자 추가(자유 역할 + 팀에서 선택) → 저장" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    l = leaf
    song = User.find_by(name: "송쿠아")
    visit product_path(l)

    within("#detail") { find("dd[data-controller~='members'] span[data-inline-edit-target='display']").click }
    within("#detail") { click_button "담당자 추가" }
    row = all("#detail [data-members-target='row']").last
    within(row) do
      find("input[name='members[][role]']").set("마케팅")
      find("select").find(:option, text: "송쿠아").select_option
    end
    within("#detail") { click_button "저장" }

    assert_selector "#detail", text: "마케팅", wait: 5
    assert_equal song, l.reload.member_for("마케팅")
  end

  test "담당자 행 삭제(x) → 저장 시 wipe" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    l = leaf
    n = l.product_members.count
    assert n.positive?
    visit product_path(l)
    within("#detail") { find("dd[data-controller~='members'] span[data-inline-edit-target='display']").click }
    assert_selector "#detail [data-members-target='row']", count: n # 폼 열림 = n행
    # 첫 행 삭제 — 작은 아이콘 버튼은 좌표클릭이 불안정 → JS 클릭
    page.execute_script("document.querySelector(\"#detail [data-members-target='row'] [data-action*='members#remove']\").click()")
    assert_selector "#detail [data-members-target='row']", count: n - 1, wait: 5 # DOM에서 1행 제거 확인
    within("#detail") { click_button "저장" }
    assert_no_selector "#detail input[name='members[][role]']", wait: 5 # 저장 후 풀 리렌더(폼 숨김) 대기
    assert_equal n - 1, l.reload.product_members.count, "삭제된 행은 저장 시 제거"
  end

  def js_click(css)
    find(css, visible: :all).execute_script("this.click()")
  end
end
