# 작업실 멤버 추가 단일 엔드포인트(모달 "사람 추가" 폼 전용, V2). 서버가 이메일로 자동 분기한다 — 관리자
# 가시 범위의 기존 계정(이 작업실 addable 후보)이면 즉시 스코프 grant(재로그인 불요), 처음 보는 이메일이면
# 초대 링크 발급. 두 경로 모두 기존 로직을 재사용한다(MemberAdministration#create_scoped_grant!/
# create_scoped_invitation! — 중복 구현 없음). 인가/역할 게이트도 초대·grant 컨트롤러와 동일 체인
# (require_domain_actor → resolve_member_scope → authorize_member_write! → scoped_role_permitted?). 기존
# invitations·role_assignments 엔드포인트는 존치(전사 관리·직접 grant·회수). 에러 표면은 R9 기존 문구 유지.
class WorkspaceMembershipsController < ApplicationController
  include MemberAdministration

  before_action :require_domain_actor, only: :create

  def create
    scope = resolve_member_scope
    # 2단 인가(T3): 대표 레코드(작업실→대표 루트 제품)로 authorize → 관할 밖/tenant-wide는 자연 deny(403·감사).
    authorize_member_write!(scope[:target])
    role_key = params[:role_key].to_s
    # D4: 작업실 경로는 팀 역할 4종만 — 전사 전용 역할 위조 추가 차단(R9 flash+redirect).
    unless scoped_role_permitted?(scope, role_key)
      return redirect_to member_admin_redirect,
                         alert: "이 역할은 작업실에 추가할 수 없습니다 — 관리자·멤버·뷰어·외부 협력 중에서 선택하세요."
    end

    if (account = addable_candidate(scope))
      add_existing_member(account, role_key, scope)
    else
      invite_new_member(role_key, scope)
    end
  end

  private

  # 즉시 추가 분기 판정 = dashboard 모달이 렌더한 addable 관계와 동일 규율(AdminScope.addable_accounts_for) 위에서
  # normalize한 이메일을 대소문자 무시로 조회. 작업실 스코프일 때만(모달은 항상 scope_workspace_id 전송) 후보를
  # 찾고, 매치가 없으면 nil → 초대 경로. 이 관계가 "동료 · 즉시 추가" 표시의 출처와 동일해 UI-서버 드리프트 불가.
  def addable_candidate(scope)
    return nil unless scope[:type] == "workspace"
    email = params[:email].to_s.strip.downcase
    Authz::AdminScope.addable_accounts_for(current_account, scope[:workspace]).find_by("lower(email) = ?", email)
  end

  def add_existing_member(account, role_key, scope)
    create_scoped_grant!(account_id: account.id, role_key: role_key, scope: scope)
    redirect_to member_admin_redirect, notice: "작업실 멤버로 추가했습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to member_admin_redirect, alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[idempotent] duplicate role grant ignored account=#{account.id} role=#{role_key} tenant=#{Current.tenant_id}")
    redirect_to member_admin_redirect, alert: "이미 부여된 권한입니다."
  end

  def invite_new_member(role_key, scope)
    _invitation, raw = create_scoped_invitation!(email: params[:email], role_key: role_key, scope: scope)
    flash[:invite_link] = invite_url(raw)
    redirect_to member_admin_redirect, notice: "초대를 만들었습니다 — 링크를 복사해 전달하세요."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to member_admin_redirect, alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[idempotent] duplicate pending invitation ignored tenant=#{Current.tenant_id} role=#{role_key}")
    redirect_to member_admin_redirect, alert: "이 이메일로 대기 중인 초대가 이미 있습니다 — 기존 초대를 취소 후 재발급하세요."
  end
end
