require "test_helper"

# S2 방어코드 검증: approval_requests_controller의 멱등/no-op/rescue 분기(감사 인벤토리 ② — 존재하나 테스트 0).
#  · 동일 버전 리뷰요청 2회      → 멱등(행 1개, 우아)
#  · reviewed 버전에 재요청       → terminal no-op "이미 검토 확인된 버전입니다."(create L1 가드)
#  · confirm 2회(순차)            → 두 번째는 정책(pending?) 게이트에서 403(rescue 아님 — 정직한 실제 거동)
#  · confirm RecordNotUnique      → 사전 스텝 시드로 유니크 위반 유도 → "이미 처리된 리뷰입니다." rescue 라인 실도달
#  · submit RecordNotUnique       → 동시 INSERT 레이스 시뮬레이션(stub) → "이미 리뷰 요청된 버전입니다." rescue
#  · 이미 배정된 리뷰 claim        → requested_reviewer_ids.none? 실패 → 403(기존 커버 재확인)
# setup=시드 + 김쿠아(owner) 로그인. 대상=CO0001 outer_box v5(시드 리뷰요청 없음 — 청정 슬레이트).
class EdgeResubmitTest < ActionDispatch::IntegrationTest
  def v = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                 .component_versions.find_by!(version_number: 5)
  def req_for = ApprovalRequest.find_by(component_version_id: v.id)
  def lee = Account.find_by!(email: "lee@cooa.dev")

  test "S2 동일 버전 리뷰요청 2회 → 멱등(행 1개·우아·pending 유지)" do
    post approval_requests_path, params: { component_version_id: v.id }
    assert_equal 1, ApprovalRequest.where(component_version_id: v.id).count

    post approval_requests_path, params: { component_version_id: v.id } # 재요청(순차) — find_or_initialize라 UPDATE
    assert_response :redirect
    assert_equal 1, ApprovalRequest.where(component_version_id: v.id).count, "재요청은 새 행을 만들지 않음(멱등)"
    assert_equal "pending", req_for.status
  end

  test "S2 reviewed 버전에 재요청 → terminal no-op '이미 검토 확인된 버전입니다.'(새 행/전이 없음)" do
    post approval_requests_path, params: { component_version_id: v.id } # pending
    req = req_for
    sign_in_as(lee)                                                     # SoD 만족(요청자 kim ≠ lee)
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status

    sign_in_as(Account.find_by!(email: "kim@cooa.dev"))
    assert_no_difference [ "ApprovalRequest.count", "ApprovalStep.count" ] do
      post approval_requests_path, params: { component_version_id: v.id } # 이미 reviewed → L1 가드 no-op
    end
    assert_equal "이미 검토 확인된 버전입니다.", flash[:notice]
    assert_equal "reviewed", req.reload.status
  end

  test "S2 confirm 2회(순차) → 두 번째는 정책(pending?) 게이트에서 403(rescue 미도달·정직한 거동)" do
    post approval_requests_path, params: { component_version_id: v.id }
    req = req_for
    sign_in_as(lee)
    post confirm_approval_request_path(req)
    assert_equal "reviewed", req.reload.status

    # 두 번째 confirm: confirm_review?는 record.pending?를 요구 → reviewed면 인가 거부(403). "이미 처리된…"
    # rescue(RecordNotUnique)는 순차 경로에서 도달 불가 — 동시성 백스톱임을 이 단언이 못박는다.
    post confirm_approval_request_path(req)
    assert_response :forbidden
    assert_equal "reviewed", req.reload.status
  end

  test "S2 confirm RecordNotUnique rescue 실도달 → '이미 처리된 리뷰입니다.'(사전 스텝 시드로 유니크 위반)" do
    post approval_requests_path, params: { component_version_id: v.id } # pending
    req = req_for
    # 동시성 시뮬레이션: 다른 확인자가 이미 스텝을 남긴 상태(unique (tenant, approval_request_id)).
    # status는 pending 유지 → 정책은 통과하고 confirm_review!의 approval_steps.create!가 RecordNotUnique.
    req.approval_steps.create!(approver_id: User.find_by!(name: "박쿠아").id, decision: "confirmed", acted_at: Time.current)

    sign_in_as(lee)
    post confirm_approval_request_path(req)
    assert_response :redirect
    assert_equal "이미 처리된 리뷰입니다.", flash[:notice], "confirm RecordNotUnique rescue 라인 실도달"
    assert_equal "pending", req.reload.status, "update!(reviewed)는 create! 예외로 롤백 — pending 유지"
  end

  test "S2 submit RecordNotUnique rescue → '이미 리뷰 요청된 버전입니다.'(동시 INSERT 레이스 시뮬레이션)" do
    # find_or_initialize 특성상 순차로는 도달 불가한 동시성 백스톱(confirm의 line-34와 대칭) — 클래스 메서드를
    # 임시 교체해 동시 INSERT 레이스를 재현하고 rescue 분기(우아한 flash)를 회귀 잠금한다.
    stub_class_method(ApprovalRequest, :submit_for!) { raise ActiveRecord::RecordNotUnique, "simulated race" }
    post approval_requests_path, params: { component_version_id: v.id }
    assert_response :redirect
    assert_equal "이미 리뷰 요청된 버전입니다.", flash[:notice]
  ensure
    restore_class_method(ApprovalRequest, :submit_for!)
  end

  private

  # minitest/mock가 이 번들(minitest 6)에 없어, 동시성 백스톱 재현용으로 클래스 메서드를 안전하게 임시
  # 교체·복원하는 최소 헬퍼(교체본은 블록 실행 시 raise). restore는 반드시 ensure에서 호출.
  def stub_class_method(klass, name, &replacement)
    (@__stubbed_originals ||= {})[[ klass, name ]] = klass.method(name)
    klass.singleton_class.send(:define_method, name) { |*, **| replacement.call }
  end

  def restore_class_method(klass, name)
    original = @__stubbed_originals&.delete([ klass, name ])
    klass.singleton_class.send(:define_method, name, original) if original
  end

  test "S2 이미 배정된 리뷰의 claim → 403(requested_reviewer_ids.none? 실패·기존 커버 재확인)" do
    lee_user = User.find_by!(email: "lee@cooa.dev")
    post approval_requests_path, params: { component_version_id: v.id, reviewer_ids: [ lee_user.id ] } # lee 배정
    req = req_for
    assert_includes req.requested_reviewer_ids, lee_user.id

    sign_in_as(lee) # 이미 배정된 리뷰어라도 claim은 '미배정'만 대상 → 거부
    assert_no_difference -> { req.approval_request_reviewers.count } do
      post claim_approval_request_path(req)
    end
    assert_response :forbidden
  end
end
