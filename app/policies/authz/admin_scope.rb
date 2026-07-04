module Authz
  # 멤버 관리(로스터·초대·grant)의 "스코프 문맥" (Stage 4 T3 — 인가 2단 재구성). 왜 필요한가:
  # scoped grant는 Organization 레코드 평가에 안 잡힌다(ResourceScope.product_for(Organization)=nil →
  # scope_chain 밖) → scoped brand_admin은 `authorize current_organization, :manage_members?` 경로를 절대
  # 통과 못 한다. 이 모듈이 액터의 관리 스코프를 분류해, 컨트롤러가 tenant-wide면 조직 레코드로 · scoped
  # brand_admin이면 자기 브랜드 제품 레코드로 authorize하게 한다(policy 신설 없이 verify_authorized 정직).
  #
  # brand_admin을 브랜드 루트 product-scope로 부여 = 그 브랜드의 팀 admin(스키마·모델이 이미 허용 —
  # owner만 tenant-wide 강제). PermissionMatrix는 무변경(record-dependent 리졸버가 스코프를 자연 제한).
  module AdminScope
    module_function

    # 반환:
    #   :all           — tenant-wide manage_members 보유(owner/brand_admin tenant-wide) → 전 조직 관리.
    #   [Product, …]   — product-scope brand_admin grant의 대상 제품들 → 그 서브트리(들)만 관리.
    #   nil            — 멤버 관리 권한 없음.
    def for(account)
      return nil unless account

      tw_roles = RoleAssignment.active.where(account_id: account.id).tenant_wide.pluck(:role_key)
      return :all if tw_roles.any? { |rk| PermissionMatrix.allows?(rk, "manage_members") }

      products = RoleAssignment.active.where(account_id: account.id, role_key: "brand_admin")
                               .where.not(scope_product_id: nil).includes(:scope_product)
                               .filter_map(&:scope_product).uniq
      products.presence
    end

    # 서브트리 product_ids에 스코프 grant를 가진 계정 id들 — 단, tenant-wide grant 보유 계정은 제외
    # (그들은 전역 멤버 = tenant-wide admin 소관). scoped 로스터(T3)·브랜드 멤버 요약(T4) 공용. N+1 없음.
    def scoped_member_account_ids(product_ids)
      product_ids = Array(product_ids)
      return [] if product_ids.empty?

      base = RoleAssignment.active
      scoped = base.where(scope_product_id: product_ids)
                   .or(base.where(scope_component_id: Component.where(product_id: product_ids).select(:id)))
                   .distinct.pluck(:account_id)
      return [] if scoped.empty?

      tenant_wide = RoleAssignment.active.tenant_wide.where(account_id: scoped).distinct.pluck(:account_id)
      scoped - tenant_wide
    end
  end
end
