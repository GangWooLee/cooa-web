# 버전 리뷰 워크플로(리프레임). 버전 뷰에서 리뷰 요청/검토 확인이 여기로 온다. 리뷰는 버전에 앵커 —
# 디자이너는 스크리닝 없이 요청, RA가 검토 중 스크리닝 수행. create=리뷰 요청+콘텐츠 스냅샷; confirm=stale
# 재검(변경됨→deny)+SoD(정책). 전이는 audit_log 1행. "고쳐야 함"은 피드백(annotation) 채널 — 변경 요청 폐지.
class ApprovalRequestsController < ApplicationController
  # create/claim은 도메인 액터(연결 User) 필수 — submitter_id/reviewer_id는 User FK라 미브리지 계정이면
  # 500(NOT NULL·AuditLog fail-closed)이 난다. 공용 가드로 fail-closed 403(E4 — 기존 인라인 2곳 대체).
  before_action :require_domain_actor, only: %i[create claim]

  # create = 리뷰 요청(component_version 기준). 버전의 소유 제품이 verb를 게이트. reviewer_ids로 담당자 지정.
  def create
    cv = ComponentVersion.find(params[:component_version_id])
    authorize cv, :submit_for_approval?
    # due_at은 선택적 마감일(기록·표시 전용, 검증/과거 제한 없음). normalized_due_at이 blank→nil 정규화 +
    # date-only 입력을 그날의 end_of_day로 변환(마감일=그날의 끝까지). reviewer_ids와 달리 스칼라라 화이트리스트 불요.
    req = ApprovalRequest.submit_for!(cv, submitter_id: current_account.user_id,
                                          reviewer_ids: sanitized_reviewer_ids(cv),
                                          due_at: normalized_due_at)
    # L1: 이미 검토 확인된(terminal) 버전에 직접 POST → no-op. 오해소지 audit/notice 방지.
    return redirect_back(fallback_location: root_path, status: :see_other, notice: "이미 검토 확인된 버전입니다.") if req.reviewed?
    audit_transition!(req, action: "submit_for_approval", before: nil)
    redirect_back fallback_location: root_path, status: :see_other, notice: submit_notice(req)
  rescue ActiveRecord::RecordNotUnique # 동시 요청 → 멱등, 500 아님
    redirect_back fallback_location: root_path, status: :see_other, notice: "이미 리뷰 요청된 버전입니다."
  end

  def confirm
    req = ApprovalRequest.find(params[:id])
    authorize req, :confirm_review? # M2 SoD(owner 포함) + pending + actor present
    before = req.status
    begin
      req.confirm_review!(reviewer_id: current_account.user_id) # stale 재검은 원자 tx 내부
    rescue ApprovalRequest::StaleReviewedTuple
      audit_stale(req)
      return redirect_back fallback_location: root_path, status: :see_other,
                           alert: "검토 내용이 변경되어 확인할 수 없습니다. 변경 내용을 다시 검토하세요."
    rescue ActiveRecord::RecordNotUnique # 동시 처리 → 이미 결정됨, 500 아님
      return redirect_back fallback_location: root_path, status: :see_other, notice: "이미 처리된 리뷰입니다."
    end
    audit_transition!(req, action: "confirm_review", before: before)
    redirect_back fallback_location: root_path, status: :see_other, notice: "검토 확인되었습니다."
  end

  # claim = 미배정 pending 리뷰 자기배정. claim?는 HARD approve verb + SoD + 미지정을 게이트(정책).
  # add_reviewer!의 유니크 백스톱이 더블클릭/동시 요청을 RecordNotUnique로 거르고 여기서 멱등 처리.
  def claim
    req = ApprovalRequest.find(params[:id])
    authorize req, :claim?
    # 요청은 이미 RLS 트랜잭션 안(Authentication#scope_to_tenant) — arr_tenant_request_reviewer_key 위반이 그
    # tx를 통째로 abort시키면 이후 AuditLog INSERT가 InFailedSqlTransaction. requires_new(=SAVEPOINT)로 격리 →
    # 위반은 세이브포인트만 롤백하고 아래 rescue가 멱등 처리(바깥 tx는 온전). Stage 3 role_assignments 직접
    # grant와 동일 관례 — "rescue 후 DB 호출 없음"이라는 취약한 불변식에 의존하지 않는다.
    begin
      ApprovalRequest.transaction(requires_new: true) { req.add_reviewer!(current_account.user_id) }
    rescue ActiveRecord::RecordNotUnique # 더블클릭/동시 claim → 멱등
      Rails.logger.info("[idempotent] duplicate claim ignored req=#{req.id} account=#{current_account.id}")
      return redirect_back fallback_location: reviews_path, status: :see_other, notice: "이미 맡으신 리뷰입니다."
    end
    # confirm/submit의 audit_transition! 래퍼는 status before/after 전용이라 claim은 공용 audit!로 직접(after=배정 reviewer).
    # action 키 "claim"은 정책 query(claim?)명과 일치 — deny 감사(application_controller pundit 경로)도 같은
    # 키를 유도하므로 allow·deny를 한 action으로 상관 가능(confirm_review/submit_for_approval와 동일 불변식).
    audit!(action: "claim", resource_type: "ApprovalRequest", resource_id: req.id,
           outcome: "allow", before: nil, after: { "reviewer_id" => current_account.user_id })
    redirect_back fallback_location: reviews_path, status: :see_other,
                  notice: "리뷰를 맡았습니다 — '내게 요청된 리뷰'에 추가되었습니다."
  end

  private

  # 전이 → 감사(allow). 요청 tenant tx와 원자: 실패 시 전이도 롤백(감사 없는 리뷰 없음). action 키
  # (submit_for_approval/confirm_review)는 정책 query명과 일치 — deny 감사도 같은 키. 요청 메타는 공용 audit!.
  def audit_transition!(req, action:, before:)
    audit!(action: action, resource_type: "ApprovalRequest", resource_id: req.id, outcome: "allow",
           before: (before ? { "status" => before } : nil), after: { "status" => req.status })
  end

  def audit_stale(req)
    audit!(action: "confirm_review", resource_type: "ApprovalRequest", resource_id: req.id,
           outcome: "deny", denial_reason: "stale_reviewed_tuple")
  end

  # 마감일은 그날의 끝까지 유효 — date 입력(YYYY-MM-DD)을 해당 날짜의 end_of_day 인스턴트로 저장(표시·강조
  # 전용, 게이팅 없음). 이렇게 하면 overdue?의 엄격 < 비교는 불변인 채로, 마감일 당일 자정부터가 아니라 그날이
  # 끝나야 초과가 된다("7.10까지"=그날 끝까지의 업무 관례). 시간까지 들어온 값(향후 datetime 입력)은 그대로
  # 존중하는 방어적 파싱. blank·파싱불가는 nil(마감 없음) — 검증 없음 관례 유지.
  def normalized_due_at
    raw = params[:due_at].presence
    return nil if raw.nil?

    instant = Time.zone.parse(raw)
    return nil if instant.nil?

    raw.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? instant.end_of_day : instant
  rescue ArgumentError # 범위 밖 날짜 등 → 마감 없음으로 관대 처리(검증 미도입 관례)
    nil
  end

  # 지정 리뷰어는 서버측에서 후보 풀(권한 평면 — 브랜드 루트 서브트리 스코프 + tenant-wide grant)로 제한
  # (임의 id 방어; 요청자 제외는 모델 sync_requested_reviewers!). 후보 정의는 리뷰 패널 체크박스와 단일
  # 출처(ReviewCandidates) — UI에 뜬 후보만 지정 가능. 상한 캡(S3, .first(20)): 과도한 지정 방어. UI 후보
  # 목록은 무캡(스크롤 가드만) — 20 초과 지정분은 여기서 잘린다(의도된 비대칭, 서버 동작 불변).
  def sanitized_reviewer_ids(component_version)
    (Array(params[:reviewer_ids]).map(&:to_i).uniq & ReviewCandidates.user_ids_for(component_version)).first(20)
  end

  # 지정 리뷰어가 있으면 그들에게 요청됨을 안내. 없으면 M1 소프트(적격 리뷰어 부재는 차단 아닌 안내).
  def submit_notice(req)
    if req.requested_reviewers.any?
      "#{req.requested_reviewers.map(&:name).join(', ')}님에게 리뷰를 요청했습니다."
    elsif EligibleApproverService.any?(exclude_user_id: req.submitter_id)
      "리뷰 요청이 제출되었습니다 — 리뷰어를 지정하지 않아 자격 리뷰어 누구나 확인할 수 있습니다."
    else
      "리뷰 요청됨 — 아직 검토 가능한 구성원(요청자와 다른 리뷰어)이 없습니다."
    end
  end
end
