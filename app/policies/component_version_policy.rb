# ComponentVersion 정책. ADR-002 §4.3: route_for_review는 external_collaborator·contributor 등이 갖는
# "검토 요청 상한" verb다 — 전용 엔드포인트 없이 submit_for_approval 게이트를 통해 실효화한다. 리뷰 요청
# 게이트(뷰 _review_panel:26 · approval_requests#create:12)가 policy(cv).submit_for_approval?만 인정하면,
# route_for_review만 가진 외부 협력자의 "다 올렸으니 검토해 주세요" 루프가 403으로 막혀 제품 밖(메일·메신저)으로
# 새어나간다. 그래서 두 verb를 OR로 묶어 submit 게이트를 통과시킨다 — 뷰·컨트롤러 둘 다 이 술어를 경유하므로
# 자동 캐스케이드(별도 엔드포인트/뷰 수정 불요). SoD·확인은 불변: 요청은 pending일 뿐, 확인은 여전히
# ApprovalRequestPolicy#confirm_review?(approve verb ∨ 지정 리뷰어 + ≠요청자)가 게이트한다.
class ComponentVersionPolicy < ApplicationPolicy
  def submit_for_approval? = can?(:submit_for_approval) || can?(:route_for_review)
end
