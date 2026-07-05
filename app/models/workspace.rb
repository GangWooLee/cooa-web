# 작업실(Workspace) — 복수 루트 제품을 담는 상위 컨테이너(WS-track). "루트=작업실 1:1" 가정을 실체화:
# 하나의 작업실이 여러 루트 트리를 담을 수 있다. 멤버십·초대·가시성의 스코프 단위(scope_workspace_id).
# products.workspace_id는 루트에만 실린다(자식은 brand_root로 도출) — has_many :products = 이 작업실의 루트들.
class Workspace < ApplicationRecord
  include TenantScoped

  # 루트 제품들(products.workspace_id FK). RESTRICT라 제품이 매달린 작업실은 삭제 불가 — 앱에서도 동일 계약.
  has_many :products, dependent: :restrict_with_exception, inverse_of: :workspace

  validates :name, presence: { message: "— 이름을 입력해 주세요" },
                   length: { maximum: 200, message: "— 200자를 넘을 수 없습니다" }

  scope :ordered, -> { order(:position, :id) }
end
