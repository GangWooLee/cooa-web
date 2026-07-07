require "test_helper"

# 인가 매트릭스 HTTP 강제(Wave 1). 8개 순수 역할 × ~20 핵심 엔드포인트를 파라미터라이즈해, 각 엔드포인트의
# "HTTP 결과(2xx/3xx allow · 403/303 deny)"가 Authz::PermissionMatrix와 일치하는지 어서트한다. 기대값은
# 손으로 쓰지 않고 PermissionMatrix.allows?(role, verb)에서 도출한다 — 매트릭스↔컨트롤러 드리프트를 잡는
# 자기갱신 테스트(정책 유닛 policy_matrix_test / 컨트롤러 단발 authorization_test 와 상보, HTTP 평면 커버).
#
# 순수 역할 계정: 시드 페르소나는 역할이 섞여 있어(kim=owner+brand_admin, lee=ra_reviewer+approver) 매트릭스
# 귀속이 흐려진다 → 역할당 순수 tenant-wide 계정을 직접 만들어(pure_account) 신원↔역할을 1:1로 고정한다.
#
# ── 엔드포인트 → verb 매핑(각 컨트롤러의 authorize 호출 실측 · file:line 근거) ──
#   products#show            view_product              app/controllers/products_controller.rb:8
#   component_versions#show  view_component_version    app/controllers/component_versions_controller.rb:6
#   screenings#screening     view_screening_findings   app/controllers/screenings_controller.rb:6
#   dashboard#index          (policy_scope, authorize 없음 → 전 역할 allow) app/controllers/dashboard_controller.rb:2
#   settings#show            (ProfilePolicy self-only → 전 역할 allow)      app/controllers/settings_controller.rb:9
#   members#index            list_tenant_accounts      app/controllers/members_controller.rb:9 (MemberAdministration#authorize_member_read!)
#   products#create          manage_product            app/controllers/products_controller.rb:32
#   products#update          manage_product            app/controllers/products_controller.rb:47
#   products#destroy         manage_product            app/controllers/products_controller.rb:61
#   components#create        upload_version            app/controllers/components_controller.rb:7
#   components#destroy       upload_version            app/controllers/components_controller.rb:45
#   component_versions#create upload_version           app/controllers/component_versions_controller.rb:34
#   screenings#run_screening run_screening             app/controllers/screenings_controller.rb:13
#   annotations#create       leave_feedback            app/controllers/annotations_controller.rb:9
#   approval_requests#create submit_for_approval ∨ route_for_review (ComponentVersionPolicy 오버라이드로 OR — 외부
#     협력자 검토 요청 활성화) app/controllers/approval_requests_controller.rb:12 / app/policies/component_version_policy.rb
#   approval_requests#confirm approve*  (손-핀: confirm_review? = 비-리뷰어 순수계정에선 can?(:approve)로 환원) app/controllers/approval_requests_controller.rb:28 / app/policies/approval_request_policy.rb:6
#   approval_requests#claim  approve*  (손-핀: claim? = can?(:approve) + 미배정)                  app/controllers/approval_requests_controller.rb:47 / app/policies/approval_request_policy.rb:13
#   invitations#create       manage_members            app/controllers/invitations_controller.rb (MemberAdministration#authorize_member_write!:26)
#   role_assignments#create  manage_members            app/controllers/role_assignments_controller.rb:18 (authorize_member_write!)
#   workspace_memberships#create manage_members        app/controllers/workspace_memberships_controller.rb:14 (authorize_member_write!)
#   workspaces#create/update/destroy manage_product    app/controllers/workspaces_controller.rb:12,26,38 (authorize current_organization, :manage_product?)
#
# ── 손-핀 예외(EXCEPTIONS) ──
#   · dashboard#index · settings#show — 도메인 verb가 아니라 정책(policy_scope / self-only)이 게이트 → 전 역할 allow.
#   · approval_requests#confirm/#claim — SoD·미배정 조건부 술어. 순수 tenant-wide 계정은 결코 시드 요청의
#     제출자/지정 리뷰어가 아니므로 두 술어가 can?(:approve)로 환원 → verb "approve"로 도출(주석에 SoD 근거 명시).
#   · destroy 계열 — 데이터 파괴라 루프 마지막 배치 + 전용 일회용 타깃(hero 등 공유 시드 불변).
class AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  # allow → 2xx/3xx(리다이렉트 허용) · deny → GET html은 303(root 리다이렉트)·그 외는 403(ApplicationController#deny_access:68).
  ALLOW = 200..399

  # 엔드포인트 스펙: verb(매트릭스 동사) 또는 all_allow(정책 게이트) · deny_status · request(람다=instance_exec).
  # 순서: 읽기(전부 allow) → 비파괴 쓰기 → 파괴(마지막·일회용 타깃). request 람다는 self=테스트 인스턴스로
  # instance_exec 되어 헬퍼(hero_v5 등)·path 헬퍼·get/post를 그대로 부른다.
  ENDPOINTS = [
    # ── 읽기(GET) ──
    { name: "dashboard#index",         all_allow: true,               request: -> { get root_path } },
    { name: "products#show",           verb: "view_product",          request: -> { get product_path(hero_product) } },
    { name: "component_versions#show", verb: "view_component_version", request: -> { get component_version_path(hero_v5) } },
    { name: "screenings#screening",    verb: "view_screening_findings", request: -> { get screening_component_version_path(hero_v5) } },
    { name: "settings#show",           all_allow: true,               request: -> { get settings_path } },
    { name: "members#index",           verb: "list_tenant_accounts", deny_status: 303, request: -> { get members_path } },

    # ── 비파괴 쓰기 ──
    { name: "products#create",  verb: "manage_product", request: -> { post products_path, params: { product: { kind: "item", name: "mx-new" } } } },
    { name: "products#update",  verb: "manage_product", request: -> { patch product_path(hero_product), params: { product: { channel: "mx" } } } },
    { name: "components#create", verb: "upload_version", request: -> { post product_components_path(hero_product) } },
    { name: "component_versions#create", verb: "upload_version",
      # version_params(require :component_version)가 authorize 이전에 파싱됨 → deny 역할도 유효 파라미터를 실어야
      # ParameterMissing(400)가 아닌 정상 403이 난다. require_artwork=true라 allow 역할은 실제 파일이 있어야 저장(2xx/3xx).
      request: -> { post component_component_versions_path(hero_component),
                    params: { component_version: { artwork: fixture_file_upload("box.jpg", "image/jpeg"), change_reason: "mx" } } } },
    { name: "screenings#run_screening", verb: "run_screening", request: -> { post run_screening_component_version_path(hero_v5) } },
    { name: "annotations#create", verb: "leave_feedback",
      request: -> { post component_version_annotations_path(hero_v5),
                    params: { box_x: 10, box_y: 10, box_w: 5, box_h: 5, category: "오탈자", body: "mx feedback" } } },
    # 리뷰 요청 게이트 = submit_for_approval ∨ route_for_review(ComponentVersionPolicy#submit_for_approval? OR).
    # verbs(OR)로 도출 → external_collaborator·approver·brand_admin(route_for_review 보유)이 deny→allow로 플립.
    { name: "approval_requests#create", verbs: %w[submit_for_approval route_for_review],
      request: -> { post approval_requests_path, params: { component_version_id: hero_v5.id } } },
    # 손-핀: confirm_review? = 비-리뷰어·비-제출자 순수계정에선 can?(:approve)로 환원(정책 approval_request_policy.rb:6).
    { name: "approval_requests#confirm", verb: "approve",
      request: -> { post confirm_approval_request_path(seed_review_request) } },
    # 손-핀: claim? = can?(:approve) + pending + 미배정(정책:13). 미배정 요청(claim_request, reviewer 0명)이 대상.
    { name: "approval_requests#claim", verb: "approve",
      request: -> { post claim_approval_request_path(claim_request) } },
    { name: "invitations#create", verb: "manage_members",
      request: -> { post invitations_path, params: { email: "mx-inv@x.dev", role_key: "viewer" } } },
    { name: "role_assignments#create", verb: "manage_members",
      # scope_product_id 필수 — 미지정이면 컨트롤러가 authorize 이전에 redirect(tenant 스코프 거부, role_assignments_controller.rb:16).
      request: -> { post role_assignments_path, params: { account_id: grantee.id, role_key: "viewer", scope_product_id: hero_product.id } } },
    { name: "workspace_memberships#create", verb: "manage_members",
      request: -> { post workspace_memberships_path, params: { email: "mx-wm@x.dev", role_key: "viewer", scope_workspace_id: cica_workspace.id } } },
    { name: "workspaces#create", verb: "manage_product", request: -> { post workspaces_path, params: { name: "mx-ws" } } },
    { name: "workspaces#update", verb: "manage_product", request: -> { patch workspace_path(disposable_ws), params: { name: "mx-ws-upd" } } },

    # ── 파괴(마지막·전용 일회용 타깃) ──
    { name: "components#destroy", verb: "upload_version", request: -> { delete component_path(disposable_component) } },
    { name: "products#destroy",   verb: "manage_product", request: -> { delete product_path(disposable_product) } },
    { name: "workspaces#destroy", verb: "manage_product", request: -> { delete workspace_path(disposable_ws) } }
  ].freeze

  # 8역할 각각 = 1 테스트 메서드(내부 ENDPOINTS 루프). 부모 setup이 매 테스트에서 자동 reseed + kim 로그인
  # (test_helper.rb:34-37) → 각 메서드는 순수 계정을 만들고 sign_in_as로 전환(리시드 비용 8회로 한정).
  RoleAssignment::ROLE_KEYS.each do |role_key|
    define_method(:"test_matrix_enforcement_for_#{role_key}") { run_matrix_for(role_key) }
  end

  # ── 스코프 격리(HTTP 매트릭스 gap — 기존 brand_scope/scoped_invite 와 중복 없는 축만) ──

  # choi = external_collaborator를 CO0200(시카) 제품 하나에만 보유 → 같은 테넌트라도 hero(CO0001)는 roles_on
  # 공집합 → view_product deny. GET html이라 303(root 리다이렉트) + deny 감사.
  test "스코프 격리: choi(CO0200 product-scope)의 hero(CO0001) products#show는 HTTP 차단" do
    sign_in_as(Account.find_by!(email: "choi@partner.example"))
    before = deny_audit_count
    get product_path(Product.find_by!(code: "CO0001"))
    assert_response :see_other
    assert_redirected_to root_path
    assert_operator deny_audit_count, :>, before, "격리 위반 시도는 deny 감사로 기록"
  end

  # 정브랜 = brand_admin을 비타민C 작업실(workspace-scope)에만 보유 → 시카 작업실 멤버 추가는 관할 밖 →
  # authorize_member_write!가 대표 레코드(시카 루트)로 deny. POST라 403 + 미생성 + deny 감사.
  test "스코프 격리: 정브랜(비타민C workspace-scope)의 시카 작업실 workspace_memberships#create는 HTTP 차단" do
    sign_in_as(Account.find_by!(email: "jung@cooa.dev"))
    cica_ws = Product.find_by!(name: "시카 수딩 크림").workspace
    before = deny_audit_count
    assert_no_difference [ "Invitation.count", "RoleAssignment.count" ] do
      post workspace_memberships_path, params: { email: "isolation@x.dev", role_key: "viewer", scope_workspace_id: cica_ws.id }
    end
    assert_response :forbidden
    assert_operator deny_audit_count, :>, before
  end

  private

  # 역할 하나에 대해 전 엔드포인트 HTTP 결과 == 매트릭스 를 어서트.
  def run_matrix_for(role_key)
    prepare_disposable_targets!
    sign_in_as(pure_account(role_key))

    before_deny = deny_audit_count
    expected_allow = expected_deny = 0
    actual_allow = actual_deny = 0

    ENDPOINTS.each do |ep|
      allowed = endpoint_allows?(ep, role_key)
      instance_exec(&ep[:request])

      if allowed
        expected_allow += 1
        actual_allow += 1 if ALLOW.include?(response.status)
        assert_includes ALLOW, response.status,
                        "#{role_key} / #{ep[:name]}: 매트릭스=ALLOW 인데 status=#{response.status}"
      else
        expected_deny += 1
        deny_status = ep[:deny_status] || 403
        actual_deny += 1 if response.status == deny_status
        assert_equal deny_status, response.status,
                     "#{role_key} / #{ep[:name]}: 매트릭스=DENY 인데 status=#{response.status}"
      end
    end

    # 교차검증: allow/deny 카운트가 기대와 정확히 일치(엔드포인트 단위 어서션의 합산 무결성).
    assert_equal expected_allow, actual_allow, "#{role_key}: ALLOW 엔드포인트 수 불일치"
    assert_equal expected_deny, actual_deny, "#{role_key}: DENY 엔드포인트 수 불일치"

    # deny 감사 스팟체크(역할당 1회) — deny가 하나라도 있으면 append-only 감사에 deny 행이 늘어야 한다.
    if expected_deny.positive?
      assert_operator deny_audit_count, :>, before_deny, "#{role_key}: deny는 audit_log(outcome=deny)에 기록되어야"
    end
  end

  # 순수 역할 계정: User(도메인 액터) + Account(active, 데모 테넌트) + tenant-wide RoleAssignment 1건.
  # 참고 패턴 = workspace_lifecycle_test.rb:15 make_account. 시드 의존 없음(역할 귀속 순수화).
  def pure_account(role_key)
    user = User.create!(name: "pure-#{role_key}", role: "pm", email: "pure-#{role_key}@matrix.dev", avatar_color: "#334455")
    acc  = Account.create!(tenant_id: Current.tenant_id, user: user, email: user.email, status: "active")
    RoleAssignment.create!(account: acc, tenant_id: Current.tenant_id, role_key: role_key,
                           scope_type: "tenant", granted_at: Time.current)
    acc
  end

  # verb(단일) 또는 verbs(OR 집합 — 예: 리뷰 요청 = submit_for_approval ∨ route_for_review). 어느 verb라도
  # 매트릭스가 허용하면 allow(정책의 OR 술어와 도출을 일치시킨다).
  def endpoint_allows?(ep, role_key)
    return true if ep[:all_allow]
    (ep[:verbs] || [ ep[:verb] ]).any? { |v| Authz::PermissionMatrix.allows?(role_key, v) }
  end

  # 파괴/부작용 엔드포인트의 전용 일회용 타깃(공유 시드 불변 유지). 매 테스트 reseed 후 새로 만든다.
  def prepare_disposable_targets!
    @disposable_ws = Workspace.create!(name: "mx-disposable-ws", tenant_id: Current.tenant_id, position: 9999)
    @disposable_product = Product.create!(name: "mx-disp-product", kind: "item", product_type: "기획", position: 9998)
    @disposable_component = hero_product.components.create!(name: "mx-disp-comp", component_type: "etc", position: 9997)
    @grantee = Account.create!(tenant_id: Current.tenant_id, email: "mx-grantee@x.dev", status: "active")
    # claim 대상 = 미배정(reviewer 0명) pending 요청. 제출자=kim(순수계정과 반드시 다름 → SoD submitter_distinct 충족).
    claim_version = Product.find_by!(code: "CO0100").components.find_by!(component_type: "outer_box")
                          .component_versions.find_by!(current: true)
    kim_user = User.find_by!(email: "kim@cooa.dev")
    @claim_request = ApprovalRequest.submit_for!(claim_version, submitter_id: kim_user.id, reviewer_ids: [])
  end

  # ── 시드 고정 타깃(메모이즈) ──
  def hero_product = @hero_product ||= Product.find_by!(code: "CO0001")
  def hero_component = @hero_component ||= hero_product.components.find_by!(component_type: "outer_box")
  def hero_v5 = @hero_v5 ||= hero_component.component_versions.find_by!(version_number: 5)
  def cica_workspace = @cica_workspace ||= Product.find_by!(name: "시카 수딩 크림").workspace

  # 시드 리뷰 요청 = kim→lee pending(us5=CO0000 30ml outer_box v5, db/seeds.rb:287). CO0000L 아님.
  def seed_review_request
    @seed_review_request ||= begin
      us5 = Product.find_by!(code: "CO0000").components.find_by!(component_type: "outer_box")
                   .component_versions.find_by!(version_number: 5)
      ApprovalRequest.find_by!(component_version_id: us5.id)
    end
  end

  def grantee = @grantee
  def disposable_ws = @disposable_ws
  def disposable_product = @disposable_product
  def disposable_component = @disposable_component
  def claim_request = @claim_request

  def deny_audit_count = AuditLog.where(outcome: "deny").count
end
