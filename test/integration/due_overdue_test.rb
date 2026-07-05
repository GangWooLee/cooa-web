require "test_helper"

# Stage 5 P2: 마감일(due_at) + overdue 표면. 세 축을 회귀 잠금 —
#   (1) 폼 관통     — 리뷰 요청 POST의 due_at이 저장된다(create permit).
#   (2) 배지 정책   — pending_review_count(Segment A) 불변 + overdue는 별도 warn 배지로 병기(내 A만·bounded).
#   (3) B 행 강조   — Segment B의 overdue 행만 warn 토큰 강조(B는 여전히 미배지 — 행 강조만).
# 기본 로그인 = kim(owner·전 권한·적격 approver). 시드 요청은 v5(kim→lee)뿐 → kim의 A/B는 아래에서 심는 것만.
class DueOverdueTest < ActionDispatch::IntegrationTest
  def outer_box = Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
  def vnum(n) = outer_box.component_versions.find_by!(version_number: n)
  def sidebar_pending = css_select("aside#app-sidebar span.bg-cooa").first&.text.to_i
  def sidebar_overdue = css_select("aside#app-sidebar span.bg-warn").first&.text.to_i

  # (1) 폼 관통: kim(owner)이 due_at을 실어 리뷰 요청 → 저장.
  test "리뷰 요청 폼의 due_at이 관통 저장된다" do
    v = vnum(1)
    post approval_requests_path, params: { component_version_id: v.id, due_at: "2026-12-31" }
    assert_response :redirect
    assert_equal Date.new(2026, 12, 31), ApprovalRequest.find_by!(component_version_id: v.id).due_at.to_date
  end

  test "due_at 미지정 요청은 마감 없음(nil)" do
    v = vnum(1)
    post approval_requests_path, params: { component_version_id: v.id }
    assert_nil ApprovalRequest.find_by!(component_version_id: v.id).due_at
  end

  # (1b) end-of-day 시맨틱: date-only 입력은 그날의 끝(end_of_day)까지 유효 → 마감일 당일 낮 동안은 overdue
  # 아님, end_of_day 경과 후에만 overdue("7.10까지"=그날 끝까지). travel_to로 결정론(실시간 상대값 금지).
  test "date-only 마감일은 그날의 end_of_day로 저장 — 당일 낮엔 overdue 아님, 자정 넘겨야 overdue" do
    v = vnum(1)
    post approval_requests_path, params: { component_version_id: v.id, due_at: "2026-07-10" }
    req = ApprovalRequest.find_by!(component_version_id: v.id)
    assert_equal Date.new(2026, 7, 10), req.due_at.to_date
    assert_equal "23:59:59", req.due_at.strftime("%H:%M:%S"), "date 입력 → 그날의 end_of_day 인스턴트"

    travel_to Time.zone.local(2026, 7, 10, 13, 0, 0) { assert_not req.overdue?, "마감일 당일 낮 → 그날의 끝까지 유효(아직 overdue 아님)" }
    travel_to Time.zone.local(2026, 7, 11, 0, 0, 1) { assert req.overdue?, "end_of_day 경과 → overdue" }
  end

  # (2) 배지: 내가 지정 리뷰어인 pending 2건(1 overdue) → pending 배지=2(불변), overdue warn 배지=1.
  test "pending 배지는 불변, overdue는 별도 warn 배지로 병기(내 Segment A만)" do
    lee = User.find_by!(email: "lee@cooa.dev").id
    kim = User.find_by!(email: "kim@cooa.dev").id
    ApprovalRequest.submit_for!(vnum(1), submitter_id: lee, reviewer_ids: [ kim ], due_at: 1.day.ago)      # overdue
    ApprovalRequest.submit_for!(vnum(2), submitter_id: lee, reviewer_ids: [ kim ], due_at: 1.day.from_now) # 미래

    get root_path
    assert_response :success
    assert_equal 2, sidebar_pending, "pending_review_count = 내 Segment A 전체(overdue 포함) — 정책 불변"
    assert_equal 1, sidebar_overdue, "overdue 배지 = 내 Segment A 중 마감 초과분만"
  end

  test "overdue 없으면 warn 배지 미노출(pending 배지만)" do
    lee = User.find_by!(email: "lee@cooa.dev").id
    kim = User.find_by!(email: "kim@cooa.dev").id
    ApprovalRequest.submit_for!(vnum(1), submitter_id: lee, reviewer_ids: [ kim ], due_at: 1.day.from_now)

    get root_path
    assert_equal 1, sidebar_pending
    assert_empty css_select("aside#app-sidebar span.bg-warn"), "overdue 0 → warn 배지 없음"
  end

  # (3) Segment B: kim(적격 owner)의 미배정 큐. overdue 행만 warn 강조(future 행은 무강조) → text-warn 정확히 1.
  test "Segment B의 overdue 행만 warn 강조된다(B는 미배지·행 강조만)" do
    lee = User.find_by!(email: "lee@cooa.dev").id
    ApprovalRequest.submit_for!(vnum(4), submitter_id: lee, reviewer_ids: [], due_at: 2.days.ago)       # overdue B
    ApprovalRequest.submit_for!(vnum(6), submitter_id: lee, reviewer_ids: [], due_at: 5.days.from_now)  # future B

    get reviews_path
    assert_response :success
    assert_select "aside#app-sidebar span.bg-warn", false, "Segment B는 배지 없음(행 강조만)"
    assert_select "span.text-warn", { count: 1 }, "overdue B 행만 warn — future 행은 무강조"
  end
end
