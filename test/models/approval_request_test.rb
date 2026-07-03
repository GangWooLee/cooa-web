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
end
