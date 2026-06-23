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
    assert_equal ["레티놀 3% 세럼", "미국", "30ml"], leaf.self_and_ancestors.map(&:name)
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
end
