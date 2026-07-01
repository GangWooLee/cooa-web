# 적격 리뷰어 조회(소프트 신호). 요청자와 구별된, 검토 verb(approve) 보유 신원(owner·approver)이 있는지 —
# 리뷰 요청 UI의 소프트 안내("리뷰어 미배정")에 쓰인다(하드 차단 폐지). 현 테넌트 RLS 컨텍스트에서 동작.
# scope_id IS NULL = 테넌트 전역. (M-4 시장관할 폐지 → market 필터 제거.)
module EligibleApproverService
  ELIGIBLE_ROLES = %w[owner approver].freeze

  module_function

  def eligible_user_ids(exclude_user_id: nil)
    RoleAssignment.active.where(role_key: ELIGIBLE_ROLES, scope_id: nil)
                  .joins(:account).distinct.pluck("accounts.user_id")
                  .compact - [exclude_user_id].compact
  end

  def any?(exclude_user_id: nil)
    eligible_user_ids(exclude_user_id: exclude_user_id).any?
  end
end
