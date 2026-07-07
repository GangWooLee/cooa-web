class ComponentsController < ApplicationController
  include Positionable

  # 파괴는 감사(allow)를 남기므로 도메인 액터 가드 선행(E4) — 미브리지 계정은 AuditLog.record!의 fail-closed
  # raise(500)에 닿기 전 403으로 막는다(products/workspaces#destroy와 동일 규약).
  before_action :require_domain_actor, only: :destroy

  # 항목(제품)에 구성요소 즉시 추가 — 기본 이름 후 인라인 명명
  def create
    product = Product.find(params[:product_id])
    authorize product, :upload_version?
    # 이름=고정값·position=서버 계산이라 검증 실패 여지가 사실상 없음 → create! 유지(비-bang 불요, E3).
    c = product.components.create!(name: "제목 없음 구성요소", position: next_position(product.components))
    redirect_to product_path(product, rename_component: c.id)
  end

  # 이름변경(인라인) — 빈 이름은 무시
  def update
    component = Component.find(params[:id])
    authorize component, :upload_version?
    name = params.dig(:component, :name).to_s.strip
    return redirect_to product_path(component.product_id) if name.blank? # 빈 이름은 무시(기존 동작)

    if component.update(name: name)
      redirect_to product_path(component.product_id)
    else
      # 입력 검증 실패(이름 길이 200 초과 등, S1)는 500 표면화가 아니라 flash 안내로 우아하게(E3 정합).
      redirect_to product_path(component.product_id),
                  alert: component.errors.full_messages.to_sentence.presence || "이름을 저장하지 못했습니다."
    end
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
    versions = component.component_versions.count # 삭제 전 — 연쇄 삭제될 버전 수(파괴 후엔 셀 수 없음)
    component.destroy
    audit_destroy!(component, versions)
    redirect_to product_path(product_id)
  end

  private

  # 파괴 감사(allow) — workspaces#audit_workspace! 패턴. resource_id = 파괴된 구성요소 id(객체는 destroy 후에도
  # id 보유). after = 파괴 요약(이름 + 연쇄 삭제된 버전 수).
  def audit_destroy!(component, versions)
    AuditLog.record!(action: "component.destroy", resource_type: "Component", resource_id: component.id,
                     outcome: "allow", after: { name: component.name, versions: versions },
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end
end
