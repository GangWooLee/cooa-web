require "application_system_test_case"

# 사이드바 우클릭 컨텍스트 메뉴(req5) + 스크리닝 스캔·순차 reveal(req1·2)
class SidebarCtxTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  def hero_version
    Product.find_by(code: "CO0001").components.find_by(component_type: "outer_box").component_versions.detect(&:current)
  end

  test "사이드바 우클릭 → 컨텍스트 메뉴 + 삭제" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    leaf = Product.find_by(code: "CO0100")
    visit root_path
    # 합성 contextmenu 디스패치(좌표 우클릭은 불안정) — 노드는 닫힌 details 안일 수 있어 visible: :all
    node = find("aside [data-node-id='#{leaf.id}']", visible: :all)
    node.execute_script("this.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:120,clientY:220}))")
    assert_selector "[data-tree-ctx-target='menu']:not(.hidden)", wait: 5
    within("[data-tree-ctx-target='menu']") do
      assert_text "경로 복사"
      assert_text "이름 변경"
      accept_confirm { find("button", text: "삭제").click }
    end
    assert_no_selector "aside [data-node-id='#{leaf.id}']", wait: 5
    assert_not Product.exists?(leaf.id)
  end

  test "스크리닝 ran=1 → 스캔 후 결과 카드 순차 표시(reveal)" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    v = hero_version
    ScreeningService.new(v, "JP").run!(requested_by: User.first)
    visit "/versions/#{v.id}/screening?ran=1"
    # 초기엔 결과가 숨김(opacity-0) → JS가 스캔 후 reveal하여 보이게 됨
    assert_selector "[data-screening-target='finding']:not(.opacity-0)", wait: 10
  end
end
