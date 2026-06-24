class ProductPropertiesController < ApplicationController
  # 커스텀 속성 즉시 추가 — 기본 키명 후 인라인 명명
  def create
    product = Product.find(params[:product_id])
    pos = (product.product_properties.maximum(:position) || -1) + 1
    prop = product.product_properties.create!(name: "속성", position: pos)
    redirect_to product_path(product, rename_property: prop.id)
  end

  # 키 이름변경 OR 값 편집(단일 필드 인라인). 빈 키는 무시(키가 사라지지 않게).
  def update
    prop = ProductProperty.find(params[:id])
    attrs = params.require(:product_property).permit(:name, :value)
    attrs.delete(:name) if attrs.key?(:name) && attrs[:name].to_s.strip.blank?
    prop.update(attrs)
    redirect_to product_path(prop.product_id)
  end

  def destroy
    prop = ProductProperty.find(params[:id])
    pid = prop.product_id
    prop.destroy
    redirect_to product_path(pid)
  end
end
