class ProductsController < ApplicationController
  # ② 데이터 매핑 = 제품 클릭 상세보기 (허브) — 트리 노드
  def show
    @product = Product.includes(:owner, :parent, :children, product_members: :user,
                                components: { component_versions: :ingredients }).find(params[:id])
    @ancestors = @product.self_and_ancestors
  end
end
