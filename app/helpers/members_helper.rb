module MembersHelper
  # 제품 트리(tree_preorder → [[node, depth], …]) → 들여쓴 <select> 옵션쌍([label, id]). depth만큼 전각
  # 공백으로 계층을 표현한다(스코프 초대 폼 + 로스터 인라인 grant 폼 공용). 값=제품 id, 라벨=들여쓴 이름.
  def scope_product_options(tree)
    tree.map { |node, depth| [ ("　" * depth) + node.name, node.id ] }
  end
end
