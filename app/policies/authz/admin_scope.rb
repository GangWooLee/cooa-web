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

      active = RoleAssignment.active.where(account_id: account.id)
      return :all if active.tenant_wide.pluck(:role_key).any? { |rk| PermissionMatrix.allows?(rk, "manage_members") }

      # 계약(판단): Workspace가 아니라 그 작업실의 **루트 제품들**을 반환한다 — 하류(authorize scope.first ·
      # subtree_ids(scope))가 이미 Product 계약이라 WorkspacePolicy 신설·전 소비처 재작성 없이 workspace 스코프를
      # 수용한다(minimalism). workspace-scope brand_admin(백필된 jung) → 그 작업실 루트들 · 루트 대상 product-scope
      # brand_admin(하위호환) → 그 제품. record-dependent 리졸버가 스코프를 자연 제한하므로 매트릭스는 무변경.
      admin = active.where(role_key: "brand_admin")
      ws_ids = admin.where.not(scope_workspace_id: nil).distinct.pluck(:scope_workspace_id)
      products = Product.roots.where(workspace_id: ws_ids).to_a
      products |= admin.where.not(scope_product_id: nil).includes(:scope_product).filter_map(&:scope_product)
      products.uniq.presence
    end

    # 서브트리 product_ids에 스코프 grant를 가진 계정 id들 — 단, tenant-wide grant 보유 계정은 제외
    # (그들은 전역 멤버 = tenant-wide admin 소관). scoped 로스터(T3)·브랜드 멤버 요약(T4) 공용. N+1 없음.
    def scoped_member_account_ids(product_ids)
      product_ids = Array(product_ids)
      return [] if product_ids.empty?

      # product_ids는 관례상 서브트리(루트 포함) → 루트의 workspace_id로 관련 작업실 도출. 그 작업실에 workspace
      # grant를 가진 계정도 "스코프 멤버"에 포함(WS-track). 루트만 workspace_id를 실으므로 이 조회로 충분.
      ws_ids = Product.where(id: product_ids).where.not(workspace_id: nil).distinct.pluck(:workspace_id)
      base = RoleAssignment.active
      scoped = base.where(scope_product_id: product_ids)
                   .or(base.where(scope_component_id: Component.where(product_id: product_ids).select(:id)))
      scoped = scoped.or(base.where(scope_workspace_id: ws_ids)) if ws_ids.any?
      scoped = scoped.distinct.pluck(:account_id)
      return [] if scoped.empty?

      tenant_wide = RoleAssignment.active.tenant_wide.where(account_id: scoped).distinct.pluck(:account_id)
      scoped - tenant_wide
    end

    # "이 작업실에 추가 가능한 계정" 관계(모달 combobox ⓐ · /workspace_memberships 즉시추가 분기의 단일 규율).
    # = 관리자 가시 범위 ∩ 이 작업실 비-스코프(아직 멤버 아님) ∩ 비-tenant-wide(전역 멤버는 이미 전 작업실 접근).
    # dashboard 렌더(제안 목록)와 membership 컨트롤러의 분기가 같은 관계를 공유해 "동료면 즉시 추가"가 표시·서버
    # 판정에서 코드로 일치한다(UI-서버 드리프트 불가). :all=전 조직 · Array(scoped admin)=자기 서브트리 스코프
    # 멤버만(가시 범위 내 — 리크 없음) · nil=권한 없음(none). N+1 없음(배치).
    # subtree_ids: 호출부(컨트롤러)가 요청-스코프로 이미 계산한 이 작업실의 서브트리 id를 주입하면
    # member_account_ids_for_workspace의 중복 subtree 확장을 재사용한다(nil이면 내부 재계산 — 하위호환).
    def addable_accounts_for(account, workspace, subtree_ids: nil)
      base = case (scope = self.for(account))
      when :all  then Account.all
      when Array then Account.where(id: scoped_member_account_ids(Product.subtree_ids(scope.map(&:id))))
      else return Account.none
      end
      exclude = member_account_ids_for_workspace(workspace, subtree_ids: subtree_ids).to_set |
                RoleAssignment.active.tenant_wide.distinct.pluck(:account_id).to_set
      base.includes(:user).where.not(id: exclude.to_a).order(:created_at)
    end

    # 작업실 멤버 계정 ids = 그 작업실 workspace-scope grant ∪ 서브트리 product/component-scope grant, tenant-wide
    # 제외. 빈 작업실(서브트리 0)도 workspace grant 멤버를 표면화한다 — 제품 파생 scoped_member_account_ids는
    # product_ids가 비면 조기반환([])이라 workspace grant를 놓치므로, 작업실을 직접 받는 이 진입점이 W3 멤버 요약·
    # 패널 멤버셋(빈 작업실 포함)의 단일 출처. N+1 없음(배치 쿼리).
    def member_account_ids_for_workspace(workspace, subtree_ids: nil)
      subtree_ids ||= Product.subtree_ids(workspace.products.pluck(:id))
      base = RoleAssignment.active
      scoped = base.where(scope_workspace_id: workspace.id)
      if subtree_ids.any?
        scoped = scoped.or(base.where(scope_product_id: subtree_ids))
                       .or(base.where(scope_component_id: Component.where(product_id: subtree_ids).select(:id)))
      end
      account_ids = scoped.distinct.pluck(:account_id)
      return [] if account_ids.empty?

      tenant_wide = RoleAssignment.active.tenant_wide.where(account_id: account_ids).distinct.pluck(:account_id)
      account_ids - tenant_wide
    end
  end
end
