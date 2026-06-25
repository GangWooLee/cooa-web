require "application_system_test_case"

# 선택 필드(커스텀 속성 값·코드·채널)는 빈값으로 비울 수 있어야 함(필수=이름은 되돌림)
class InlineClearableTest < ApplicationSystemTestCase
  setup { Rails.application.load_seed }

  test "커스텀 속성 값은 빈값으로 비울 수 있음(clearable)" do
    page.driver.browser.manage.window.resize_to(1440, 900)
    prop = ProductProperty.find_by(name: "용량")
    refute_equal "", prop.value.to_s, "전제: 값이 채워져 있음"
    visit product_path(prop.product)
    assert_selector "#prop_value_#{prop.id}", visible: :all, wait: 10
    sleep 0.6 # Stimulus 연결 정착
    # 값 display 클릭 → 입력칸 열기(요소 캐시 없이 id로 fresh 조회 — stale 방지)
    page.execute_script("document.getElementById('prop_value_#{prop.id}').closest('dd').querySelector(\"[data-inline-edit-target='display']\").click()")
    assert_selector "#prop_value_#{prop.id}", visible: true, wait: 5
    fill_in "prop_value_#{prop.id}", with: ""
    find("#prop_value_#{prop.id}").send_keys(:enter)
    sleep 0.7
    assert_equal "", prop.reload.value.to_s, "선택 필드(값)는 빈값 저장(되돌리지 않음)"
  end
end
