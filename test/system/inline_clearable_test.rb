require "application_system_test_case"

# 선택 필드(커스텀 속성 값·코드·채널)는 빈값으로 비울 수 있어야 함(필수=이름은 되돌림)
class InlineClearableTest < ApplicationSystemTestCase
  test "커스텀 속성 값은 빈값으로 비울 수 있음(clearable)" do
    page.current_window.resize_to(1440, 900)
    prop = ProductProperty.find_by(name: "용량")
    refute_equal "", prop.value.to_s, "전제: 값이 채워져 있음"
    visit product_path(prop.product)
    assert_selector "#prop_value_#{prop.id}", visible: :all, wait: 10
    sleep 0.6 # Stimulus 연결 정착
    # 편집 열기 + 빈값 + Enter 저장을 한 스크립트로(재find·blur 레이스/stale 회피)
    page.execute_script(<<~JS)
      var dd = document.getElementById('prop_value_#{prop.id}').closest('dd');
      dd.querySelector("[data-inline-edit-target='display']").click();
      var el = document.getElementById('prop_value_#{prop.id}');
      el.value = '';
      el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    JS
    deadline = Time.now + 8
    sleep 0.2 while prop.reload.value.to_s != "" && Time.now < deadline # 저장(redirect) 반영 대기
    assert_equal "", prop.reload.value.to_s, "선택 필드(값)는 빈값 저장(되돌리지 않음)"
  end
end
