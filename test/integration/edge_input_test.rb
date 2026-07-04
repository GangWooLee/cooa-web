require "test_helper"

# S1 입력 위생: (1) XSS 이스케이프 게이트 — 저장은 허용하되 렌더 시 원시 태그가 절대 새지 않음을 엄밀히 단언
# (원시 문자열 부재 + 동일 이스케이프 함수(ERB::Util.html_escape) 산출물 존재). (2) 모델 length 검증 —
# 한도+1 거부·한도 이내 통과. (3) 이모지 허용·공백만 거부(presence). setup=시드 + 김쿠아(owner) 로그인.
#
# 주의(브리프): 앱을 raw 출력으로 바꿔보는 실험은 하지 않는다. ERB::Util.html_escape로 기대 문자열을 계산해
# "이스케이프된 형태로 존재 + 원시 형태 부재"를 이중 단언 → 게이트가 실제로 무는지 정직하게 검증.
class EdgeInputTest < ActionDispatch::IntegrationTest
  def kim = User.find_by!(email: "kim@cooa.dev")

  def hero_v(n)
    Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
           .component_versions.find_by!(version_number: n)
  end

  # ── (1) XSS 이스케이프 게이트 ──────────────────────────────────────────────
  test "S1 제품명 XSS(script) 페이로드는 렌더 시 이스케이프 · 원시 태그 부재" do
    raw = %(<script>alert('PWNPROD_a1')</script>)
    Product.create!(name: raw, kind: "item") # 모델 경로로 직접 저장(렌더 이스케이프 게이트만 검증)

    get root_path
    assert_response :success
    assert_includes @response.body, ERB::Util.html_escape(raw), "제품명은 이스케이프된 형태로 존재해야 함"
    assert_not_includes @response.body, raw, "원시 <script> 태그가 대시보드 본문에 존재하면 안 됨(html_safe 유출 금지)"
  end

  test "S1 어노테이션 코멘트 body XSS(onerror 속성)는 렌더 시 이스케이프 · 원시 부재" do
    raw = %(<img src=x onerror="alert('PWNBODY_a1')">)
    v = hero_v(5)
    ann = v.annotations.create!(box_x: 1, box_y: 1, box_w: 1, box_h: 1, category: "기타",
                                created_by: kim, seq: 99)
    ann.comments.create!(author: kim, body: raw)

    get component_version_path(v)
    assert_response :success
    assert_includes @response.body, ERB::Util.html_escape(raw), "코멘트 body는 이스케이프된 형태로 존재해야 함"
    assert_not_includes @response.body, raw, "원시 onerror 속성이 버전 화면에 존재하면 안 됨"
  end

  test "S1 커스텀 속성 값 XSS(속성 브레이크아웃)는 렌더 시 이스케이프 · 원시 부재" do
    raw = %("><script>alert('PWNPROP_a1')</script>)
    prod = Product.find_by!(code: "CO0001")
    prod.product_properties.create!(name: "위험속성", value: raw, position: 99)

    get product_path(prod)
    assert_response :success
    assert_includes @response.body, ERB::Util.html_escape(raw), "속성 값은 이스케이프된 형태로 존재해야 함"
    assert_not_includes @response.body, raw, "원시 속성 브레이크아웃 문자열이 제품 화면에 존재하면 안 됨"
  end

  # ── (2) 모델 length 검증 — 한도+1 거부, 한도 이내 통과 ─────────────────────
  test "S1 length 검증: 한도+1은 해당 속성 에러 · 한도 이내는 에러 없음" do
    v5 = hero_v(5)
    comp = v5.component
    ann = v5.annotations.create!(box_x: 1, box_y: 1, box_w: 1, box_h: 1, category: "기타",
                                 created_by: kim, seq: 98)

    # over(한도+1) → 해당 속성 에러 존재 / at(한도 정확) → 해당 속성 에러 없음(로케일 무관·속성 단위 단언)
    assert_attr_length_boundary(Product.new(name: "가" * 201), Product.new(name: "가" * 200), :name)
    assert_attr_length_boundary(Component.new(product: comp.product, name: "가" * 201),
                                Component.new(product: comp.product, name: "가" * 200), :name)
    assert_attr_length_boundary(ComponentVersion.new(component: comp, change_reason: "가" * 501),
                                ComponentVersion.new(component: comp, change_reason: "가" * 500), :change_reason)
    assert_attr_length_boundary(ann.comments.new(author: kim, body: "가" * 2001),
                                ann.comments.new(author: kim, body: "가" * 2000), :body)
  end

  test "S1 초장문 코멘트 body(한도+1) HTTP POST → 미생성 + 우아한 거부(500 아님)" do
    ann = hero_v(5).annotations.open.first
    assert_no_difference -> { ann.comments.count } do
      post annotation_comments_path(ann), params: { body: "가" * 2001 }
    end
    assert_response :redirect                 # PRG — 500이 아니라 flash 안내로 되돌림
    assert flash[:alert].present?, "길이 초과는 flash alert로 안내되어야 함"
  end

  # 어노테이션 생성은 annotation.save! + 첫 코멘트 create!의 다중 쓰기(위 standalone 코멘트 경로와 별개).
  # 초장문 첫 코멘트가 RecordInvalid를 던지면 세이브포인트가 save!까지 함께 롤백해 댕글링(코멘트 없는)
  # 어노테이션이 남지 않아야 한다(원자성 회귀 잠금). 요청은 이미 RLS tx 안이라 requires_new 없으면 평범한
  # 중첩 transaction이 바깥 tx에 JOIN되어 save!가 커밋됨 → annotations_controller의 세이브포인트 fix를 잠근다.
  test "S1 초장문 첫 코멘트로 어노테이션 생성 → 원자적 롤백(댕글링 어노테이션 미생성·500 아님)" do
    v = hero_v(5)
    assert_no_difference -> { v.annotations.count } do
      post component_version_annotations_path(v),
           params: { box_x: 10, box_y: 12, box_w: 8, box_h: 5, category: "디자인", body: "가" * 2001 }
    end
    assert_response :redirect                 # PRG — 500이 아니라 flash 안내로 되돌림
    assert flash[:alert].present?, "길이 초과는 flash alert로 안내되어야 함"
  end

  # ── (3) 이모지 허용 · 공백만 거부 ─────────────────────────────────────────
  test "S1 이모지-only 이름 허용 · 공백-only 이름 거부(presence)" do
    emoji = Product.new(name: "😀🎉", kind: "item")
    emoji.valid?
    assert_empty emoji.errors[:name], "이모지 이름은 유효(허용)"

    ws = Product.new(name: "   ", kind: "item") # normalizes(strip) → "" → presence 위반
    ws.valid?
    assert ws.errors[:name].present?, "공백만 이름은 presence로 거부되어야 함"
  end

  private

  # over 인스턴스는 attr에 에러가 있고, at(한도 정확) 인스턴스는 attr에 에러가 없음을 단언.
  # 메시지 문자열이 아니라 "속성에 에러가 붙었는가"로 판정 → 로케일/메시지 포맷에 무의존.
  def assert_attr_length_boundary(over, at, attr)
    over.valid?
    assert over.errors[attr].present?, "#{over.class}##{attr} 한도+1은 거부되어야 함"
    at.valid?
    assert_empty at.errors[attr], "#{at.class}##{attr} 한도 이내는 통과해야 함"
  end
end
