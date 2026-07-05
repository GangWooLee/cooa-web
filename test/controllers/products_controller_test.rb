require "test_helper"

# 제품 트리 CRUD — 컨트롤러/리퀘스트 레벨(속성·파라미터·연쇄·검증 즉시 포착)
class ProductsControllerTest < ActionDispatch::IntegrationTest
  def folder = Product.find_by(name: "레티놀 3% 세럼")

  # 방금 생성된 노드(리다이렉트 URL의 rename id로 정확히 특정 — 생성은 트리로 리다이렉트)
  def created_product = Product.find(@response.location[/rename=(\d+)/, 1])

  test "즉시 폴더 생성(루트) → 트리 인라인 명명 리다이렉트" do
    assert_difference -> { Product.where(kind: "folder").count }, 1 do
      post products_path, params: { product: { kind: "folder" } }
    end
    p = created_product
    assert p.folder?, "kind=folder"
    assert_equal "제목 없음 폴더", p.name
    assert_redirected_to root_path(rename: p.id) # 드로어 아님 — 트리에서 인라인 명명
  end

  test "즉시 항목 생성(폴더 하위) — 빈 구성요소" do
    f = folder
    post products_path, params: { product: { kind: "item", parent_id: f.id } }
    item = created_product
    assert item.leaf?
    assert_equal "제목 없음", item.name
    assert_equal f.id, item.parent_id
    assert_equal 0, item.components.count, "새 항목은 빈 상태"
    assert_redirected_to root_path(rename: item.id)
  end

  test "담당자 지정 생성(배열형) + 이름만 PATCH 시 담당자 보존" do
    f = folder
    kim = User.find_by(name: "김쿠아")
    post products_path, params: { product: { kind: "item", parent_id: f.id },
                                  members: [ { role: "designer", user_id: kim.id } ] }
    item = created_product
    assert_equal kim, item.member_for("designer")
    patch product_path(item), params: { product: { name: "새이름" }, inline: 1 }
    assert_equal "새이름", item.reload.name
    assert_equal kim, item.member_for("designer"), "이름만 PATCH 시(members 미전송) 담당자 보존"
  end

  test "동적 담당자 — 자유 역할 + 소유자 통합 + 미선택 행 skip" do
    item = Product.find_by(code: "CO0001")
    kim = User.find_by(name: "김쿠아")
    song = User.find_by(name: "송쿠아")
    patch product_path(item), params: { inline: 1, members: [
      { role: "소유자", user_id: kim.id },
      { role: "마케팅", user_id: song.id },
      { role: "QA", user_id: "" } # 사람 미선택 → skip
    ] }
    assert_equal 2, item.product_members.count, "미선택 행 제외"
    assert_equal kim, item.member_for("소유자")
    assert_equal song, item.member_for("마케팅")
    assert_equal "마케팅", ProductMember.find_by(role: "마케팅").role_short, "미지 역할은 원문 폴백"
  end

  test "담당자 재구성 — 제거된 행은 wipe" do
    item = Product.find_by(code: "CO0001")
    assert item.product_members.count.positive?
    kim = User.find_by(name: "김쿠아")
    patch product_path(item), params: { inline: 1, members: [ { role: "디자인", user_id: kim.id } ] }
    assert_equal 1, item.product_members.reload.count
    assert_equal kim, item.member_for("디자인")
  end

  test "트리 인라인 rename(return=tree)은 그 작업실(focus)로, 그 외는 드로어로 리다이렉트" do
    item = Product.find_by(code: "CO0001")
    patch product_path(item), params: { product: { name: "트리명" }, inline: 1, return: "tree" }
    assert_redirected_to root_path(focus: item.id) # 그 노드의 작업실 트리 + 조상 펼침(focus)
    patch product_path(item), params: { product: { name: "드로어명" }, inline: 1 }
    assert_redirected_to product_path(item)
  end

  test "트리 생성 후 해당 행이 auto-rename 마크업으로 렌더" do
    post products_path, params: { product: { kind: "folder" } }
    p = created_product
    get root_path(rename: p.id)
    assert_response :success
    assert_match %r{data-inline-edit-auto-value="true"}, @response.body
    assert_select "input#node_name_#{p.id}"
  end

  test "경로 표시 — 드로어에 전체 경로(루트 › … › self)" do
    leaf = Product.find_by(code: "CO0001")
    get product_path(leaf)
    assert_response :success
    # tenant-wide 기본 계정(kim)엔 가시 조상 = 전체 조상 → node_path_label이 전체 경로를 렌더.
    assert_includes @response.body, leaf.self_and_ancestors.map(&:name).join(" › ")
  end

  test "국가 자유입력 정규화 — 한글/코드는 코드 저장" do
    item = Product.find_by(code: "CO0001")
    patch product_path(item), params: { product: { country: "미국" }, inline: 1 }
    assert_equal "US", item.reload.country, "미국 → US (screening 매칭 보존)"
    patch product_path(item), params: { product: { country: "프랑스" }, inline: 1 }
    assert_equal "프랑스", item.reload.country, "미지 국가는 원문"
  end

  test "이름 공백 정규화(앞뒤 제거)" do
    post products_path, params: { product: { kind: "folder" } }
    p = created_product
    patch product_path(p), params: { product: { name: "  브랜드X  " } }
    assert_equal "브랜드X", p.reload.name
  end

  test "kind 는 수정에서 불변(폴더↔항목 전환 금지)" do
    f = folder
    post products_path, params: { product: { kind: "item", parent_id: f.id } }
    item = created_product
    patch product_path(item), params: { product: { name: "x", kind: "folder" } }
    assert item.reload.leaf?, "kind 변경 무시(item 유지)"
  end

  test "빈 이름 인라인 PATCH → 500 아님·이름 유지" do
    item = Product.find_by(code: "CO0001")
    patch product_path(item), params: { product: { name: "  " }, inline: 1 }
    assert_response :redirect
    assert_equal "일본", item.reload.name
  end

  test "잘못된 상위(비폴더)로 생성 → 트리 오염 없음" do
    leaf = Product.find_by(code: "CO0001") # item
    assert_no_difference -> { Product.count } do
      post products_path, params: { product: { kind: "item", parent_id: leaf.id } }
    end
    assert_response :redirect
  end

  test "E3 생성 검증 실패 시 flash alert 노출(무피드백 redirect 금지)" do
    leaf = Product.find_by(code: "CO0001") # 비폴더 부모 → 검증 거부
    post products_path, params: { product: { kind: "item", parent_id: leaf.id } }
    assert_response :redirect
    assert flash[:alert].present?, "검증 실패는 flash alert로 안내되어야 함"
  end

  test "폴더 삭제 → 하위·구성요소·버전 연쇄 제거" do
    f = folder
    descendant_ids = f.self_and_descendant_ids
    comp_ids = Component.where(product_id: descendant_ids).pluck(:id)
    ver_ids = ComponentVersion.where(component_id: comp_ids).pluck(:id)
    assert comp_ids.any?
    delete product_path(f)
    assert_redirected_to root_path
    assert_empty Product.where(id: descendant_ids)
    assert_empty Component.where(id: comp_ids)
    assert_empty ComponentVersion.where(id: ver_ids)
  end

  # ── 생성 위치(relative_to) ──
  test "생성 위치: 폴더 선택 → 자식 맨 아래" do
    f = folder
    post products_path, params: { product: { kind: "item" }, relative_to: f.id }
    item = created_product
    assert_equal f.id, item.parent_id, "폴더 선택 → 자식"
    assert_equal f.children.maximum(:position), item.position, "맨 아래"
  end

  test "생성 위치: 파일 선택 → 형제(같은 부모)" do
    leaf = Product.find_by(code: "CO0001") # 레티놀 하위
    post products_path, params: { product: { kind: "folder" }, relative_to: leaf.id }
    node = created_product
    assert_equal leaf.parent_id, node.parent_id, "파일 선택 → 형제"
  end

  test "생성 위치: 미선택 → 루트 맨 아래" do
    post products_path, params: { product: { kind: "folder" } }
    node = created_product
    assert_nil node.parent_id
    assert_equal Product.roots.maximum(:position), node.position, "루트 맨 아래"
  end

  # ── 드래그앤드롭 이동(move) ──
  def move_url(node) = move_product_path(node)

  test "move: 폴더 안으로 재배치(parent 변경 + 맨 끝)" do
    leaf = Product.find_by(code: "CO0001")
    dest = Product.find_by(name: "비타민C 브라이트닝 앰플") # 다른 폴더
    patch move_url(leaf), params: { parent_id: dest.id }
    assert_response :success
    assert_equal dest.id, leaf.reload.parent_id
    assert_equal dest.children.maximum(:position), leaf.position, "맨 끝 append"
  end

  test "move: before_id로 형제 앞 정렬" do
    f = folder
    a = f.children.create!(name: "A", kind: "folder")
    b = f.children.create!(name: "B", kind: "folder")
    patch move_url(b), params: { parent_id: f.id, before_id: a.id }
    assert_response :success
    assert b.reload.position < a.reload.position, "b가 a 앞"
  end

  test "move: 루트로 이동(parent_id 빈값)" do
    child = Product.find_by(code: "CO0001")
    patch move_url(child), params: { parent_id: "" }
    assert_response :success
    assert_nil child.reload.parent_id
  end

  test "move: 자손으로 이동 거부(순환) → 422·불변" do
    parent = folder
    child = parent.children.find_by(name: "미국") # 하위 폴더
    patch move_url(parent), params: { parent_id: child.id }
    assert_response :unprocessable_entity
    assert_nil parent.reload.parent_id, "이동 안 됨"
  end

  test "move: 비폴더(파일) 부모 거부 → 422" do
    leaf = Product.find_by(code: "CO0001")
    other = Product.find_by(code: "CO0100")
    patch move_url(other), params: { parent_id: leaf.id }
    assert_response :unprocessable_entity
  end
end
