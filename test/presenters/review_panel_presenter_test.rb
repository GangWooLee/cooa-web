require "test_helper"

# 프리젠터 계산 로직 단위 테스트(DB 불필요 — stub). 뷰 분기의 진실을 여기서 고정.
class ReviewPanelPresenterTest < ActiveSupport::TestCase
  Reviewer = Struct.new(:name)
  Req = Struct.new(:status, :reviewers) do
    def requested_reviewers = reviewers
  end

  def present(request: nil, open: 0)
    ReviewPanelPresenter.new(version: nil, request: request, open_feedback_count: open)
  end

  test "state: none / pending / reviewed" do
    assert_equal :none, present.state
    assert_equal :pending, present(request: Req.new("pending", [])).state
    assert_equal :reviewed, present(request: Req.new("reviewed", [])).state
  end

  test "open feedback + advisory 소프트 경고" do
    refute present(open: 0).open_feedback?
    assert_nil present(open: 0).confirm_warning
    assert present(open: 2).open_feedback?
    assert_match "2개", present(open: 2).confirm_warning
  end

  test "waiting_message: 지정 리뷰어 이름 or 일반 문구" do
    assert_match "이쿠아", present(request: Req.new("pending", [Reviewer.new("이쿠아")])).waiting_message
    assert_match "검토 가능한 리뷰어", present(request: Req.new("pending", [])).waiting_message
  end
end
