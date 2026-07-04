# 스코프 grant 직접 부여/회수 (Stage 3 D5) — 기존 계정을 특정 제품에 재-스코프(초대 우회 경로). 초대와 같은
# manage_members(owner/brand_admin) 게이트이며, 같은 백스톱(RoleAssignment 모델 검증 + DB CHECK)을 공유한다.
# 감사는 uuid PK라 resource_id=nil(관례)·식별자는 after 페이로드로.
class RoleAssignmentsController < ApplicationController
  include MemberAdministration

  # grant/revoke는 감사(allow)를 남긴다 — 도메인 액터(연결 User) 없는 계정이면 AuditLog.record!가
  # fail-closed로 raise(500). 공용 가드로 먼저 fail-closed 403(E4).
  before_action :require_domain_actor, only: %i[create destroy]

  def create
    # 2단 인가(T3): 항상 product 스코프 grant → scoped admin은 "대상 제품" 레코드로 authorize(자기 브랜드
    # 서브트리만 통과 · 타 브랜드는 deny). tenant-wide admin은 조직 레코드(현행 무회귀).
    authorize_member_write!(params[:scope_product_id].presence)

    # owner 제외(초대와 동일 INVITABLE_ROLE_KEYS). owner는 tenant-wide 전용이라 product 스코프가 CHECK·모델
    # 에서도 막히지만, 권한 상승 시도를 서버측에서 먼저 차단한다.
    role_key = params[:role_key].to_s
    return redirect_to(members_path, alert: "부여할 수 없는 역할입니다.") unless Invitation::INVITABLE_ROLE_KEYS.include?(role_key)

    # 요청은 이미 RLS 트랜잭션 안(Authentication#scope_to_tenant) — uniq_role_assignment_v2 위반이 그 tx를
    # 통째로 abort시키면 이후 쿼리가 InFailedSqlTransaction. requires_new(=SAVEPOINT)로 격리 → 위반은
    # 세이브포인트만 롤백하고 재부여를 아래 rescue가 멱등 처리(바깥 tx는 온전).
    grant = RoleAssignment.transaction(requires_new: true) do
      RoleAssignment.create!(
        account_id: params[:account_id], tenant_id: Current.tenant_id, role_key: role_key,
        scope_type: "product", scope_product_id: params[:scope_product_id],
        granted_by: current_account.id, granted_at: Time.current
      )
    end
    audit!("role_assignment.grant", grant)
    redirect_to members_path, notice: "스코프 권한을 부여했습니다."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to members_path, alert: e.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[idempotent] duplicate role grant ignored account=#{params[:account_id]} role=#{role_key} tenant=#{Current.tenant_id}")
    redirect_to members_path, alert: "이미 부여된 권한입니다."
  end

  def destroy
    # 스코프 grant 전용 회수 — where.not(scope_type: "tenant")로 tenant-wide grant(동료 admin·approver)를 이 경로에서
    # 제외. manage_members만으로 tenant-wide 역할까지 회수하는 신규 HTTP 능력을 차단(UI 어포던스는 스코프 배지 회수뿐 —
    # 능력과 일치, UUID 은닉에 의존하지 않음). tenant-wide id 시도는 RecordNotFound → 404.
    grant = RoleAssignment.where.not(scope_type: "tenant").find(params[:id])
    # 2단 인가(T3): scoped admin은 자기 브랜드 grant만 회수 — grant의 대상 제품(component grant면 그 소유 제품)
    # 레코드로 authorize. 타 브랜드 grant 회수 시도는 deny(403). tenant-wide admin은 조직 레코드로 통과.
    authorize_member_write!(grant.scope_product_id || grant.scope_component&.product_id)
    grant.destroy!
    audit!("role_assignment.revoke", grant)
    redirect_to members_path, notice: "스코프 권한을 회수했습니다."
  rescue LastOwnerGuard::Error => e
    # 마지막 owner grant 회수 시도(스코프 grant엔 해당 없음 — 방어). 가드가 tx 롤백 + 예외.
    redirect_to members_path, alert: e.message
  end

  private

  def audit!(action, grant)
    AuditLog.record!(action: action, resource_type: "RoleAssignment", resource_id: nil, outcome: "allow",
                     after: { account_id: grant.account_id, role_key: grant.role_key, scope_product_id: grant.scope_product_id },
                     request_id: request.request_id, source_ip: request.remote_ip, user_agent: request.user_agent)
  end
end
