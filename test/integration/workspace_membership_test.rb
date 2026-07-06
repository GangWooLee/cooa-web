require "test_helper"

# V2 서버 자동 분기(모달 "사람 추가" 단일 엔드포인트 /workspace_memberships): normalize한 이메일이 이 작업실의
# addable 후보(AdminScope 가시 ∩ 비-이미멤버 ∩ 비-tenant-wide — dashboard 모달이 렌더한 관계와 동일 규율)와
# 매치하면 즉시 스코프 grant(초대 미생성, 재로그인 불요), 아니면 초대 링크 발급(grant 미생성). 역할 위조 4종
# 화이트리스트·이미 대기초대·이미 멤버·대소문자 정규화·스코프 admin 관할 밖 차단을 서버측에서 고정한다. 기존
# invitations·role_assignments 직접 POST 엔드포인트는 존치(무회귀 — 그 스위트가 별도로 증명).
class WorkspaceMembershipTest < ActionDispatch::IntegrationTest
  setup do
    @kim  = Account.find_by!(email: "kim@cooa.dev")            # owner(tenant-wide) = AdminScope :all
    @jung = Account.find_by!(email: "jung@cooa.dev")           # brand_admin @ 비타민C(scoped)
    @choi = Account.find_by!(email: "choi@partner.example")    # external @ 시카(비타민C엔 비-멤버) = addable 후보
    @lee  = Account.find_by!(email: "lee@cooa.dev")            # approver+ra_reviewer(tenant-wide) = 이미 멤버
    @park = Account.find_by!(email: "park@cooa.dev")           # contributor(전역이지만 manage_members 없음)
    @vitc = Product.find_by!(name: "비타민C 브라이트닝 앰플")   # 작업실 루트
    @ws   = @vitc.workspace
  end

  test "기존 addable 후보 이메일 → 즉시 스코프 grant · 초대 미생성 · 재로그인 불요" do
    sign_in_as(@kim)
    assert_difference "RoleAssignment.count", 1 do
      assert_no_difference "Invitation.count" do
        post workspace_memberships_path, params: {
          email: @choi.email, role_key: "contributor",
          scope_workspace_id: @ws.id, return_to_workspace: @ws.id
        }
      end
    end
    assert_redirected_to workspace_path(@ws)                    # 온 자리(작업실)로 복귀
    ra = @choi.role_assignments.find_by!(scope_workspace_id: @ws.id)
    assert_equal [ "contributor", "workspace", @ws.id ], [ ra.role_key, ra.scope_type, ra.scope_workspace_id ]
    grant = AuditLog.where(action: "role_assignment.grant").order(:ts).last
    assert_equal [ @choi.id, "contributor", @ws.id ],
                 [ grant.after["account_id"], grant.after["role_key"], grant.after["scope_workspace_id"] ]
    follow_redirect!
    assert_match "작업실 멤버로 추가했습니다", response.body
  end

  test "미지 이메일 → 초대 링크 발급 · grant 미생성 · 작업실 스코프 · 링크 노출" do
    sign_in_as(@kim)
    assert_difference "Invitation.count", 1 do
      assert_no_difference "RoleAssignment.count" do
        post workspace_memberships_path, params: {
          email: "newcomer@partner.dev", role_key: "external_collaborator",
          scope_workspace_id: @ws.id, return_to_workspace: @ws.id
        }
      end
    end
    inv = Invitation.find_by!(email: "newcomer@partner.dev")
    assert_equal [ "workspace", @ws.id ], [ inv.scope_type, inv.scope_workspace_id ]
    assert_redirected_to workspace_path(@ws)
    follow_redirect!
    assert_match "지금 복사해 전달하세요", response.body                 # 발급 링크 배너(모달 상단)
    assert_match %r{/invite/[A-Za-z0-9_\-]+}, response.body
    assert AuditLog.where(action: "invitation.create").exists?
  end

  test "대소문자 정규화 — 대문자 이메일도 addable 후보와 매치해 즉시 grant(초대 미생성)" do
    sign_in_as(@kim)
    assert_difference "RoleAssignment.count", 1 do
      assert_no_difference "Invitation.count" do
        post workspace_memberships_path, params: {
          email: @choi.email.upcase, role_key: "viewer",
          scope_workspace_id: @ws.id, return_to_workspace: @ws.id
        }
      end
    end
    assert @choi.role_assignments.exists?(scope_workspace_id: @ws.id, role_key: "viewer")
  end

  test "스코프 admin(정브랜)은 관할 밖 계정 이메일을 즉시 추가할 수 없음(초대 경로·기존 검증 표면·미생성)" do
    # 정브랜(비타민C scoped)이 최디자(choi — 시카 external, 관할 밖) 이메일 입력: addable 아님(비가시) → 초대
    # 경로 → 이미 계정 존재 → email_not_already_member(RecordInvalid) → grant·초대 둘 다 미생성(기존 검증 표면).
    sign_in_as(@jung)
    assert_no_difference [ "RoleAssignment.count", "Invitation.count" ] do
      post workspace_memberships_path, params: {
        email: @choi.email, role_key: "contributor",
        scope_workspace_id: @ws.id, return_to_workspace: @ws.id
      }
    end
    assert_redirected_to workspace_path(@ws)
    assert_match "멤버", flash[:alert].to_s                             # "이미 멤버입니다" 기존 표면
  end

  test "역할 위조: 4종 밖(approver)은 거부 · grant·초대 미생성(R9 안내)" do
    sign_in_as(@kim)
    assert_no_difference [ "RoleAssignment.count", "Invitation.count" ] do
      post workspace_memberships_path, params: {
        email: @choi.email, role_key: "approver",
        scope_workspace_id: @ws.id, return_to_workspace: @ws.id
      }
    end
    assert_match "추가할 수 없", flash[:alert].to_s
  end

  test "이미 대기 중인 초대 이메일 재추가 → 멱등 안내 · 초대 미중복" do
    sign_in_as(@kim)
    post workspace_memberships_path, params: {
      email: "dup@partner.dev", role_key: "contributor",
      scope_workspace_id: @ws.id, return_to_workspace: @ws.id
    }
    assert_equal 1, Invitation.where(email: "dup@partner.dev").count
    assert_no_difference "Invitation.count" do
      post workspace_memberships_path, params: {
        email: "dup@partner.dev", role_key: "contributor",
        scope_workspace_id: @ws.id, return_to_workspace: @ws.id
      }
    end
    assert_match "대기 중인 초대가 이미", flash[:alert].to_s
  end

  test "이미 멤버(tenant-wide 계정) 이메일 → 초대 경로에서 거부 · grant·초대 미생성" do
    sign_in_as(@kim)
    assert_no_difference [ "RoleAssignment.count", "Invitation.count" ] do
      post workspace_memberships_path, params: {
        email: @lee.email, role_key: "contributor",
        scope_workspace_id: @ws.id, return_to_workspace: @ws.id
      }
    end
    assert_match "멤버", flash[:alert].to_s
  end

  test "manage_members 없는 계정(park)은 403 · grant·초대 미생성" do
    sign_in_as(@park)
    assert_no_difference [ "RoleAssignment.count", "Invitation.count" ] do
      post workspace_memberships_path, params: {
        email: @choi.email, role_key: "contributor", scope_workspace_id: @ws.id
      }
    end
    assert_response :forbidden
  end
end
