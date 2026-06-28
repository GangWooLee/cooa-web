class ProductPropertiesController < ApplicationController
  include Positionable

  # 커스텀 속성 즉시 추가 — 기본 키명 후 인라인 명명
  def create
    product = Product.find(params[:product_id])
    authorize product, :manage_product?
    prop = product.product_properties.create!(name: "속성", position: next_position(product.product_properties))
    redirect_to product_path(product, rename_property: prop.id)
  end

  # 키 이름변경 OR 값 편집(단일 필드 인라인). 빈 키는 무시(키가 사라지지 않게).
  def update
    prop = ProductProperty.find(params[:id])
    authorize prop, :manage_product?
    attrs = params.require(:product_property).permit(:name, :value)
    attrs.delete(:name) if attrs.key?(:name) && attrs[:name].to_s.strip.blank?
    prop.update!(attrs) # 빈 키 가드 후라 실패는 곧 버그 → 삼키지 않고 표면화
    redirect_to product_path(prop.product_id)
  end

  def destroy
    prop = ProductProperty.find(params[:id])
    authorize prop, :manage_product?
    pid = prop.product_id
    prop.destroy
    redirect_to product_path(pid)
  end
end
