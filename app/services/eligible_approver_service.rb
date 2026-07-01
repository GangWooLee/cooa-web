# 적격 리뷰어 조회(리프레임: M1 소프트 신호). 요청자와 구별된, 검토 verb(approve) 보유 신원이 있는지 —
# 리뷰 요청 UI의 소프트 안내("리뷰어 미배정")에 쓰인다(하드 차단 폐지). `owner`·`approver`만 검토 verb를
# 가짐(PermissionMatrix). 현 테넌트 RLS 컨텍스트에서 동작. scope_id IS NULL = 테넌트 전역.
module EligibleApproverService
  ELIGIBLE_ROLES = %w[owner approver].freeze

  module_function

  def eligible_user_ids(market:, exclude_user_id: nil)
    RoleAssignment.active.where(role_key: ELIGIBLE_ROLES, scope_id: nil) # expiry/join pushed to SQL (P4 ①)
                  .where("market IS NULL OR market = ?", market)
                  .joins(:account).distinct.pluck("accounts.user_id")
                  .compact - [exclude_user_id].compact
  end

  def any?(market:, exclude_user_id: nil)
    eligible_user_ids(market: market, exclude_user_id: exclude_user_id).any?
  end
end
