require "test_helper"

# 제품 자기참조 트리(노션형) 검증
class ProductTreeTest < ActiveSupport::TestCase
  setup { Rails.application.load_seed }

  test "roots + 중첩 구조" do
    assert_equal 3, Product.roots.count
    retinol = Product.find_by(name: "레티놀 3% 세럼", parent_id: nil)
    assert retinol.folder?, "루트는 폴더(자식 보유)"
    us = retinol.children.find_by(name: "미국")
    assert_equal 2, us.children.count, "미국 아래 30ml/50ml"
  end

  test "조상 경로 / depth / leaf?" do
    leaf = Product.find_by(code: "CO0000") # 30ml
    assert leaf.leaf?
    assert_equal [ "레티놀 3% 세럼", "미국", "30ml" ], leaf.self_and_ancestors.map(&:name)
    assert_equal 2, leaf.depth
  end

  test "tree_preorder 는 루트부터 사전순" do
    rows = Product.tree_preorder
    assert_equal "레티놀 3% 세럼", rows.first[0].name
    assert_equal 0, rows.first[1]
    # 미국(depth1) 바로 뒤에 30ml(depth2)
    idx = rows.index { |n, _| n.name == "미국" && n.folder? }
    assert_equal 2, rows[idx + 1][1]
  end

  test "name 정규화(앞뒤 공백) + presence" do
    p = Product.create!(name: "  미국  ", kind: "folder")
    assert_equal "미국", p.name
    assert_not Product.new(name: "   ", kind: "item").valid?, "공백만 → 무효"
  end

  test "code 비어있으면 중복 허용" do
    f = Product.find_by(name: "레티놀 3% 세럼")
    a = Product.create(name: "a", kind: "item", parent: f)
    b = Product.create(name: "b", kind: "item", parent: f)
    assert a.persisted? && b.persisted?, "코드 nil 다수 허용"
  end

  test "parent_options_for 는 자기·하위·비폴더 제외" do
    f = Product.find_by(name: "레티놀 3% 세럼")
    opts = Product.parent_options_for(f)
    ids = opts.map { |n, _| n.id }
    assert_not_includes ids, f.id, "자기 제외"
    f.self_and_descendant_ids.each { |did| assert_not_includes ids, did, "하위 제외" }
    assert opts.all? { |n, _| n.folder? }, "폴더만"
  end

  test "비폴더·하위로 이동 금지(검증)" do
    f = Product.find_by(name: "레티놀 3% 세럼")
    nonfolder = Product.find_by(code: "CO0100") # 다른 트리의 item
    f.parent_id = nonfolder.id
    assert_not f.valid?, "비폴더는 상위 불가"
    f.reload
    f.parent_id = f.children.first.id # 하위(순환)
    assert_not f.valid?, "하위로 이동 불가"
  end
end
