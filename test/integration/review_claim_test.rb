require "test_helper"

# Stage 1: 투-세그먼트 인박스 + claim(자기배정). park(contributor)가 리뷰어 미지정으로 제출 → 적격
# owner/approver의 Segment B(미배정)에 노출 → claim으로 Segment A(내게 요청된 리뷰)로 이동 → confirm.
# setup(test_helper)=시드 + kim 로그인. 각 테스트에서 sign_in_as로 신원 전환.
class ReviewClaimTest < ActionDispatch::IntegrationTest
  def hero_v5
    Product.find_by!(code: "CO0001").components.find_by!(component_type: "outer_box")
           .component_versions.find_by!(version_number: 5)
  end

  def submit_unassigned_as(email, cv)
    sign_in_as(Account.find_by!(email: email))
    post approval_requests_path, params: { component_version_id: cv.id }
    ApprovalRequest.find_by!(component_version_id: cv.id)
  end

  # add_reviewer!가 유니크 충돌을 던지도록 블록 동안만 override(레이스 창 모사). ensure로 원복 → 누수 없음.
  def with_colliding_add_reviewer
    ApprovalRequest.class_eval do
      alias_method :__orig_add_reviewer!, :add_reviewer!
      define_method(:add_reviewer!) { |_| raise ActiveRecord::RecordNotUnique, "arr_tenant_request_reviewer_key" }
    end
    yield
  ensure
    ApprovalRequest.class_eval do
      alias_method :add_reviewer!, :__orig_add_reviewer!
      remove_method :__orig_add_reviewer!
    end
  end

  test "미배정 리뷰는 적격(lee·kim)의 Segment B에 노출되고 비적격(song·park)에겐 미렌더" do
    req = submit_unassigned_as("park@cooa.dev", hero_v5)
    assert_empty req.requested_reviewer_ids, "리뷰어 미지정 제출"

    # lee(ra_reviewer+approver=적격): Segment B에 CO0001 + '내가 맡기'
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    get reviews_path
    assert_response :success
    assert_match "내가 맡을 수 있는 리뷰", response.body
    assert_match "CO0001", response.body
    assert_match "내가 맡기", response.body

    # kim(owner=적격): 노출
    sign_in_as(Account.find_by!(email: "kim@cooa.dev"))
    get reviews_path
    assert_match "내가 맡기", response.body

    # song(brand_admin, approve verb 없음=비적격): Segment B 헤더/버튼 미렌더
    sign_in_as(Account.find_by!(email: "song@cooa.dev"))
    get reviews_path
    refute_match "내가 맡을 수 있는 리뷰", response.body
    refute_match "내가 맡기", response.body

    # park(contributor=비적격, 게다가 요청자 본인): Segment B 미렌더
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    get reviews_path
    refute_match "내가 맡을 수 있는 리뷰", response.body
  end

  # 배지 baseline은 시드(kim이 CO0000 v5를 lee에게 요청)라 절대값 대신 claim 전후 +1 델타로 검증.
  def sidebar_badge = css_select("aside#app-sidebar span.bg-cooa").first&.text.to_i

  test "claim으로 자기배정 → Segment A로 이동, 사이드바 배지 +1, claim 감사(allow) +1" do
    req = submit_unassigned_as("park@cooa.dev", hero_v5)
    lee = User.find_by!(email: "lee@cooa.dev")

    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    get reviews_path
    before_badge = sidebar_badge

    assert_difference -> { AuditLog.where(action: "claim", outcome: "allow").count }, 1 do
      post claim_approval_request_path(req)
    end
    assert_match "리뷰를 맡았습니다", flash[:notice]
    assert_includes req.reload.requested_reviewer_ids, lee.id

    # 재GET: A에 CO0001 등장, 배지 +1, B에서는 소멸.
    get reviews_path
    assert_response :success
    assert_match "내게 요청된 리뷰", response.body
    assert_match "CO0001", response.body                              # A에 등장(B는 비어 있으므로 A 소속)
    assert_equal before_badge + 1, sidebar_badge, "claim이 사이드바 pending_review_count 배지에 +1"
    assert_match "맡을 수 있는 미배정 리뷰가 없습니다", response.body # B는 이제 비어 있음
  end

  test "claim 후 confirm으로 리뷰 완료 (SoD: lee≠park)" do
    req = submit_unassigned_as("park@cooa.dev", hero_v5)
    lee = User.find_by!(email: "lee@cooa.dev")

    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post claim_approval_request_path(req)
    post confirm_approval_request_path(req)

    assert_equal "reviewed", req.reload.status
    step = req.approval_steps.first
    assert_equal lee.id, step.approver_id
    assert_equal "confirmed", step.decision
  end

  # 순차 재-claim은 정책이 차단(이미 지정된 리뷰어=Segment A 소속, !requested_reviewer?). 리뷰어 행 1 유지.
  test "이미 맡은 리뷰어의 순차 재-claim은 403 (정책 가드), 리뷰어 행 1 유지" do
    req = submit_unassigned_as("park@cooa.dev", hero_v5)
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    post claim_approval_request_path(req)
    assert_equal 1, req.approval_request_reviewers.count

    post claim_approval_request_path(req) # 재-claim: lee는 이제 지정 리뷰어 → claim? false
    assert_response :forbidden
    assert_equal 1, req.reload.approval_request_reviewers.count, "중복 배정 없음"
  end

  # 동시(더블클릭) claim에서 유니크 인덱스가 삽입을 거부하는 레이스를 모사 — 컨트롤러 rescue가
  # RecordNotUnique를 멱등 notice로 변환(500 아님). 순차로는 정책이 먼저 막으므로 rescue는 동시성 백스톱:
  # 정책이 통과(미배정)한 뒤 add_reviewer!만 충돌하도록 메서드를 한시적으로 덮어 그 레이스 창을 모사한다.
  test "동시 claim 충돌(RecordNotUnique)은 rescue로 멱등 처리 — notice + see_other" do
    req = submit_unassigned_as("park@cooa.dev", hero_v5) # 미배정 = 정책 통과 상태
    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))

    with_colliding_add_reviewer do
      post claim_approval_request_path(req)
    end
    assert_response :see_other
    assert_match "이미 맡으신 리뷰입니다", flash[:notice]
    assert_equal 0, req.reload.approval_request_reviewers.count, "충돌 → 새 행 없음(멱등)"
  end

  # 비적격(song=brand_admin)·요청자(park)는 claim 불가.
  test "비적격 역할과 요청자 본인은 claim 불가 (403)" do
    req = submit_unassigned_as("park@cooa.dev", hero_v5)

    sign_in_as(Account.find_by!(email: "song@cooa.dev")) # approve verb 없음
    post claim_approval_request_path(req)
    assert_response :forbidden
    assert_empty req.reload.requested_reviewer_ids

    sign_in_as(Account.find_by!(email: "park@cooa.dev")) # 요청자 본인 + 비적격
    post claim_approval_request_path(req)
    assert_response :forbidden
    assert_empty req.reload.requested_reviewer_ids
  end

  # N+1 게이트(R5): 서로 다른 브랜드 루트의 미배정 2건 → 프리젠터의 brand_root walk가 여러 번 돈다.
  # .parent walk(N+1)면 prosopite가 raise. in-memory 맵이면 통과.
  test "Segment B 렌더는 N+1 없음 (브랜드 조상 walk in-memory 게이트)" do
    v_a = hero_v5
    v_b = Product.find_by!(code: "CO0200").components.find_by!(component_type: "outer_box")
                 .component_versions.find_by!(version_number: 2)
    sign_in_as(Account.find_by!(email: "park@cooa.dev"))
    post approval_requests_path, params: { component_version_id: v_a.id }
    post approval_requests_path, params: { component_version_id: v_b.id }

    sign_in_as(Account.find_by!(email: "lee@cooa.dev"))
    assert_no_n_plus_one { get reviews_path }
    assert_response :success
  end

  # 배지 단일 쿼리 게이트(perf 발견 5): 사이드바 리뷰 배지(pending+overdue)는 인증 페이지 렌더당
  # approval_requests ⋈ approval_request_reviewers JOIN COUNT **정확히 1회**여야 한다(COUNT(*) FILTER
  # 조건부 집계 통합). pending/overdue 별도 COUNT 2회로 되돌리면 2가 세어져 RED. Prosopite 관례로는
  # 표현 불가(대상이 '유사쿼리 반복'이 아니라 '정확한 횟수'이고, WHERE가 다른 두 COUNT는 유사쿼리로
  # 안 묶임) → sql.active_record 구독 카운터로 타협(사유 명기).
  test "사이드바 배지는 인증 페이지당 approval_requests JOIN COUNT 정확히 1회" do
    sign_in_as(Account.find_by!(email: "lee@cooa.dev")) # 시드: kim이 CO0000 v5를 lee에게 요청 → pending ≥1
    count = count_badge_count_queries { get root_path }
    assert_response :success
    assert_operator sidebar_badge, :>=, 1, "pending 배지가 실제 렌더돼야 게이트가 문다"
    assert_equal 1, count, "배지 COUNT 쿼리는 페이지당 정확히 1회(조건부 집계 통합)여야 한다"
  end

  # approval_requests ⋈ approval_request_reviewers COUNT 발화 횟수(쿼리캐시 히트 제외) 집계.
  def count_badge_count_queries
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _s, _f, _id, payload|
      next if payload[:cached] || payload[:name] == "CACHE"

      sql = payload[:sql].to_s
      n += 1 if sql.match?(/\ASELECT COUNT/i) && sql.include?("approval_requests") && sql.include?("approval_request_reviewers")
    end
    yield
    n
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
