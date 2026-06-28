class ComponentsController < ApplicationController
  include Positionable

  # 항목(제품)에 구성요소 즉시 추가 — 기본 이름 후 인라인 명명
  def create
    product = Product.find(params[:product_id])
    authorize product, :upload_version?
    c = product.components.create!(name: "제목 없음 구성요소", position: next_position(product.components))
    redirect_to product_path(product, rename_component: c.id)
  end

  # 이름변경(인라인) — 빈 이름은 무시
  def update
    component = Component.find(params[:id])
    authorize component, :upload_version?
    name = params.dig(:component, :name).to_s.strip
    component.update!(name: name) if name.present? # present 가드 후라 실패는 버그 → 표면화
    redirect_to product_path(component.product_id)
  end

  # 드래그 순서변경 — 제품 스코프 내에서만
  def reorder
    product = Product.find(params[:product_id])
    authorize product, :upload_version?
    ids = params.permit(ids: [])[:ids] || []
    Component.transaction do
      ids.each_with_index do |id, i|
        product.components.where(id: id).update_all(position: i)
      end
    end
    head :ok
  end

  # 구성요소 삭제 (버전·피드백 연쇄)
  def destroy
    component = Component.find(params[:id])
    authorize component, :upload_version?
    product_id = component.product_id
    component.destroy
    redirect_to product_path(product_id)
  end
end
