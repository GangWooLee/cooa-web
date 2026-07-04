class DashboardController < ApplicationController
  # index lists via policy_scope (load_dashboard_rows) rather than authorize — verify the scope instead.
  skip_after_action :verify_authorized, only: :index
  after_action :verify_policy_scoped, only: :index

  # ① 데이터 관리 대시보드 — 제품 트리(펼침 행). /brands/:id면 그 브랜드(루트 제품) 서브트리로 스코프
  # + 팀 멤버 요약(T4). 가시성은 policy_scope가 결정 — 비가시 브랜드(스코프 계정의 타 브랜드) 접근은
  # 기존 Scope 동작대로 redirect(같은 테넌트·비가시) 또는 404(RecordNotFound·타 테넌트/미존재).
  def index
    brand_id = params[:id].presence
    visible = load_dashboard_rows(brand_root_id: brand_id) # policy_scope 항상 호출(verify_policy_scoped 충족)
    return unless brand_id

    @brand = visible.find { |p| p.id.to_s == brand_id.to_s }
    if @brand.nil?
      raise ActiveRecord::RecordNotFound unless Product.exists?(id: brand_id) # 타 테넌트/미존재 → 404

      return redirect_to root_path, alert: "권한이 없습니다.", status: :see_other # 같은 테넌트·비가시 → 303
    end
    @brand_members = brand_member_accounts(@brand)
  end
end
