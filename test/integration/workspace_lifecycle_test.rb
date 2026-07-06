require "test_helper"

# 시나리오 ⑤ (D3/D4/D5 end-to-end · 통합): 작업실 수명주기 — 생성(이름 + 멤버 4종) → 빈 상태 진입 → 제품
# 2트리 생성 → workspace grant 멤버 접근·비멤버 차단 → 이름 변경(트리명 무관) → 제품 있는 채 삭제 거부 →
# 비우고 삭제 성공. + 역할 위조 차단(작업실 경로 4종 화이트리스트) + CRUD tenant-wide 게이트 + 4종 라벨 렌더.
class WorkspaceLifecycleTest < ActionDispatch::IntegrationTest
  setup do
    @kim  = Account.find_by!(email: "kim@cooa.dev")   # owner(tenant-wide) — 작업실 CRUD 게이트 통과
    @song = Account.find_by!(email: "song@cooa.dev")  # brand_admin(tenant-wide) — manage_members
    # 순수 workspace-scope 멤버 검증용 신규 계정(전역 grant 전무 → 접근은 오직 workspace grant로 성립).
    @member   = make_account("tf-member@cooa.dev", "TF멤버")
    @outsider = make_account("tf-outsider@cooa.dev", "외부인") # grant 전무 → 비멤버
  end

  def make_account(email, name)
    user = User.create!(name: name, role: "pm", email: email, avatar_color: "#334455")
    Account.create!(tenant_id: @kim.tenant_id, user: user, email: email, status: "active")
  end

  test "생성(이름+멤버)→빈 상태→제품 2트리→멤버 접근·비멤버 차단→이름변경→삭제 거부→비우고 삭제" do
    sign_in_as(@kim)

    # 1) 생성: 이름 + 멤버(@member = 멤버[contributor]). 작업실 + workspace-scope grant 1건.
    assert_difference [ "Workspace.count", "RoleAssignment.count" ], 1 do
      post workspaces_path, params: {
        name: "2026 리뉴얼 TF", member_ids: [ @member.id ], roles: { @member.id.to_s => "contributor" }
      }
    end
    ws = Workspace.find_by!(name: "2026 리뉴얼 TF")
    assert_redirected_to workspace_path(ws)
    ra = @member.role_assignments.sole
    assert_equal [ "contributor", "workspace", ws.id ], [ ra.role_key, ra.scope_type, ra.scope_workspace_id ]
    aud = AuditLog.where(action: "workspace.create").order(:ts).last
    assert_equal "2026 리뉴얼 TF", aud.after["name"]

    # 2) 진입 → 빈 상태(제품 0).
    follow_redirect!
    assert_response :success
    assert_match "아직 폴더나 항목이 없습니다", response.body

    # 3) 제품 2트리 생성(workspace_id 명시 = 툴바/사이드바 생성 경로) → 둘 다 이 작업실 루트.
    post products_path, params: { product: { kind: "folder" }, workspace_id: ws.id }
    tree1 = Product.order(:id).last
    post products_path, params: { product: { kind: "folder" }, workspace_id: ws.id }
    tree2 = Product.order(:id).last
    assert_equal [ ws.id, ws.id ], [ tree1.workspace_id, tree2.workspace_id ]
    assert_not_equal tree1.id, tree2.id

    # 4) workspace grant 멤버(@member)는 두 트리 모두 접근 · 비멤버(@outsider)는 차단.
    sign_in_as(@member)
    get workspace_path(ws)
    assert_response :success
    table_ids = css_select("table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
    assert_includes table_ids, tree1.id.to_s
    assert_includes table_ids, tree2.id.to_s

    sign_in_as(@outsider)
    get workspace_path(ws)
    assert_redirected_to root_path # 비멤버 = 비가시 작업실 진입 → 303
    get root_path
    assert_no_match "2026 리뉴얼 TF", response.body # 홈 카드에도 부재

    # 5) 이름 변경(작업실만 — 루트 트리 무변).
    sign_in_as(@kim)
    patch workspace_path(ws), params: { name: "2026 리뉴얼 최종" }
    assert_redirected_to workspace_path(ws)
    assert_equal "2026 리뉴얼 최종", ws.reload.name
    assert_equal [ tree1.id, tree2.id ].sort, ws.products.order(:id).pluck(:id)

    # 6) 제품 있는 채 삭제 거부(R9 flash · RESTRICT 백스톱).
    assert_no_difference "Workspace.count" do
      delete workspace_path(ws)
    end
    assert_redirected_to workspace_path(ws)
    assert_match "제품이 남아 있는", flash[:alert]

    # 7) 비우고 삭제 성공(홈 복귀 · 감사).
    tree1.destroy
    tree2.destroy
    assert_difference "Workspace.count", -1 do
      delete workspace_path(ws)
    end
    assert_redirected_to root_path
    assert AuditLog.where(action: "workspace.destroy").exists?
  end

  test "역할 위조: 작업실/제품 경로에 전사 전용 역할(approver·ra_reviewer)은 발급 거부(미생성)·4종은 정상" do
    sign_in_as(@song) # manage_members(tenant-wide)
    ws = Product.find_by!(name: "비타민C 브라이트닝 앰플").workspace
    co0100 = Product.find_by!(code: "CO0100")

    # 초대: 작업실 스코프 + approver(4종 밖) → R9 flash · 미생성.
    assert_no_difference "Invitation.count" do
      post invitations_path, params: { email: "forge@x.dev", role_key: "approver", scope_workspace_id: ws.id }
    end
    assert_match "초대할 수 없", flash[:alert].to_s

    # 직접 grant: 제품 스코프 + ra_reviewer(4종 밖) → 거부 · 미생성.
    assert_no_difference "RoleAssignment.count" do
      post role_assignments_path, params: { account_id: @member.id, role_key: "ra_reviewer", scope_product_id: co0100.id }
    end
    assert_match "부여할 수 없", flash[:alert].to_s

    # 대조: 4종(external_collaborator)은 정상 발급.
    assert_difference "RoleAssignment.count", 1 do
      post role_assignments_path, params: { account_id: @member.id, role_key: "external_collaborator", scope_product_id: co0100.id }
    end
  end

  test "작업실 CRUD는 tenant-wide 관리자만 — scoped admin(정브랜)·비관리자(park)는 생성 403" do
    jung = Account.find_by!(email: "jung@cooa.dev") # brand_admin workspace-scope(scoped, 비-전역)
    sign_in_as(jung)
    assert_no_difference "Workspace.count" do
      post workspaces_path, params: { name: "정브랜 작업실" }
    end
    assert_response :forbidden

    park = Account.find_by!(email: "park@cooa.dev") # contributor(전역이지만 manage_product 없음)
    sign_in_as(park)
    assert_no_difference "Workspace.count" do
      post workspaces_path, params: { name: "박 작업실" }
    end
    assert_response :forbidden
  end

  test "4종 라벨 렌더 — 작업실 사람 추가 폼 role select는 팀 4종(한글 라벨)만" do
    sign_in_as(@kim)
    ws = Product.find_by!(name: "비타민C 브라이트닝 앰플").workspace
    get workspace_path(ws)
    assert_response :success
    # V2: 모달 "사람 추가" 폼은 통합 엔드포인트(/workspace_memberships)로 POST(동료 즉시추가/미지 초대 자동 분기).
    opts = css_select("form[action='#{workspace_memberships_path}'] select[name='role_key'] option").map { |o| o.text.strip }
    assert_equal [ "관리자", "멤버", "뷰어", "외부 협력" ], opts, "작업실 사람 추가 폼 = 팀 4종 한글 라벨(전사 전용 역할 부재)"
  end
end
