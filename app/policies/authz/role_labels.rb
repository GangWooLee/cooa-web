module Authz
  # 역할 키 → 한글 라벨·1줄 설명(D4). authz value(role_key)는 불변 — 표시만 한글화한다(기존 테스트·감사
  # 페이로드·PermissionMatrix 전부 role_key 원문 유지). 작업실 폼은 팀 4종(WORKSPACE_ROLE_KEYS)만 노출·발급하고,
  # 전사 관리 폼은 INVITABLE 7종을 노출한다. 라벨/설명이 없는 키는 키 원문으로 폴백(안전).
  module RoleLabels
    module_function

    LABELS = {
      "owner" => "소유자",
      "brand_admin" => "관리자",
      "contributor" => "멤버",
      "viewer" => "뷰어",
      "external_collaborator" => "외부 협력",
      "ra_reviewer" => "검토자",
      "approver" => "승인자",
      "assignee" => "담당 편집자"
    }.freeze

    DESCRIPTIONS = {
      "owner" => "조직 전체 관리",
      "brand_admin" => "작업실·멤버 관리",
      "contributor" => "업로드·피드백·리뷰 요청",
      "viewer" => "열람만",
      "external_collaborator" => "업로드·피드백, 승인 불가",
      "ra_reviewer" => "검토(RA)",
      "approver" => "승인",
      "assignee" => "담당 편집"
    }.freeze

    # 작업실 경로(초대·직접 grant·생성 시 멤버)에 노출/발급하는 팀 역할 4종 — 관리자/멤버/뷰어/외부 협력.
    # 전사 전용 역할(owner·approver·ra_reviewer·assignee)은 작업실/제품 스코프로 위조 발급 불가 — 서버측
    # 화이트리스트가 곧 이 목록(MemberAdministration#scoped_role_permitted?). 폼도 이 목록만 노출한다.
    WORKSPACE_ROLE_KEYS = %w[brand_admin contributor viewer external_collaborator].freeze

    def label(role_key) = LABELS.fetch(role_key.to_s, role_key.to_s)
    def description(role_key) = DESCRIPTIONS[role_key.to_s]
    def workspace_role?(role_key) = WORKSPACE_ROLE_KEYS.include?(role_key.to_s)
  end
end
