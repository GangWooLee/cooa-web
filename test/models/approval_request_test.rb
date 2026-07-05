require "test_helper"

# add_reviewer!(claim 전용 단건 append)의 두 계약: 기존 리뷰어 보존 + 유니크 백스톱
# (arr_tenant_request_reviewer_key)이 중복을 RecordNotUnique로 거부(멱등 처리는 컨트롤러 rescue).
class ApprovalRequestTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed
    @cv = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
                 .component_versions.find_by!(version_number: 5)
    @kim  = User.find_by!(email: "kim@cooa.dev")
    @lee  = User.find_by!(email: "lee@cooa.dev")
    @park = User.find_by!(email: "park@cooa.dev")
  end

  test "add_reviewer!는 기존 리뷰어를 보존하며 단건 append (sync와 대비)" do
    req = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [ @lee.id ])
    assert_equal [ @lee.id ], req.requested_reviewer_ids

    req.add_reviewer!(@park.id)
    assert_equal [ @lee.id, @park.id ].sort, req.reload.requested_reviewer_ids.sort,
                 "sync_와 달리 기존 리뷰어(lee)를 지우지 않고 park를 추가"
  end

  test "add_reviewer!는 동일 reviewer 재호출 시 RecordNotUnique (유니크 백스톱)" do
    req = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [])
    req.add_reviewer!(@lee.id)
    assert_raises(ActiveRecord::RecordNotUnique) { req.add_reviewer!(@lee.id) }
  end

  # ── Stage 5 P2: due_at + overdue? ──────────────────────────────────────────
  # overdue? = due_at 존재 & 과거(엄격 <). 경계(due_at == now)는 아직 overdue 아님(엄격 <), 1초만 지나도 true.
  # status 무관(순수 날짜 술어 — pending 필터는 호출부 쿼리가 담당). travel_to로 시각 동결 → 경계를 결정론적으로
  # 검증(실시간 상대값 금지). DB 불요 — in-memory 인스턴스로 경계만 고정.
  test "overdue?는 nil·미래·경계(==now)에서 false, 경계 1초 경과부터 true" do
    travel_to Time.zone.local(2026, 7, 10, 12, 0, 0) do
      assert_not ApprovalRequest.new(due_at: nil).overdue?,            "마감일 없음 → overdue 아님"
      assert_not ApprovalRequest.new(due_at: 1.hour.from_now).overdue?, "미래 마감 → overdue 아님"
      assert_not ApprovalRequest.new(due_at: Time.current).overdue?,    "경계 due_at == now → 아직 overdue 아님(엄격 <)"
      assert ApprovalRequest.new(due_at: 1.second.ago).overdue?,       "경계에서 1초 경과 → overdue"
    end
  end

  test "submit_for!는 due_at 미지정 시 nil (기존 호출부 호환)" do
    req = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [])
    assert_nil req.due_at
  end

  test "submit_for!는 due_at을 관통 저장한다" do
    due = 3.days.from_now
    req = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [], due_at: due)
    assert_equal due.to_i, req.reload.due_at.to_i
  end

  test "재제출(비-terminal)은 같은 행의 due_at을 갱신한다" do
    req  = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [], due_at: 3.days.from_now)
    due2 = 10.days.from_now
    req2 = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [], due_at: due2)
    assert_equal req.id, req2.id, "버전당 1요청 — find_or_initialize로 같은 행"
    assert_equal due2.to_i, req2.reload.due_at.to_i, "비-terminal 재제출은 폼이 진실원천 → 갱신"
  end

  test "terminal(reviewed) 재제출은 no-op — due_at 불변" do
    due1 = 3.days.from_now
    req  = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [], due_at: due1)
    req.update!(status: "reviewed") # terminal로 전이
    req2 = ApprovalRequest.submit_for!(@cv, submitter_id: @kim.id, reviewer_ids: [], due_at: 10.days.from_now)
    assert req2.reviewed?, "terminal이면 그대로 반환"
    assert_equal due1.to_i, req2.due_at.to_i, "terminal no-op — 새 due_at 무시(불변)"
  end
end
