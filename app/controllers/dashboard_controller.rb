class DashboardController < ApplicationController
  # ① 데이터 관리 대시보드 — 제품 트리(펼침 행)
  def index
    @rows = Product.tree_preorder(Product.roots.includes(:children, :owner, :product_members,
                                                          components: :component_versions))
  end
end
