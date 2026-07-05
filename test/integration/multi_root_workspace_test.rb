require "test_helper"

# WS-track 핵심 신규 능력: 하나의 작업실이 **복수 루트 트리**를 담을 수 있다. "루트=작업실 1:1"을 넘어선다.
#   (a) 작업실 grant 멤버는 그 작업실의 **두 루트 모두** 가시(홈 카드 1개 · 진입 시 컨텍스트 트리 2루트 렌더).
#   (b) 비멤버(타 스코프)는 그 작업실을 보지 못한다(진입 303 · 홈 카드 부재).
#   (c) tenant-wide는 두 루트를 카드 1개(제품 합산)로 본다.
class MultiRootWorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    @kim = Account.find_by!(email: "kim@cooa.dev") # owner(tenant-wide)
    # 한 작업실에 루트 2개(브랜드A·브랜드B) + 각 루트 아래 리프 1개.
    @ws = Workspace.create!(name: "합본 작업실", position: 9)
    @root_a = Product.create!(name: "브랜드A", kind: "folder", workspace: @ws, position: 0)
    @root_b = Product.create!(name: "브랜드B", kind: "folder", workspace: @ws, position: 1)
    @leaf_a = Product.create!(name: "에이-일본", parent: @root_a, code: "MRA1", country: "JP", position: 0)
    @leaf_b = Product.create!(name: "비-미국", parent: @root_b, code: "MRB1", country: "US", position: 0)
  end

  def workspace_member
    user = User.create!(name: "합본멤버", role: "pm", email: "multi@cooa.dev", avatar_color: "#123456")
    acc  = Account.create!(tenant_id: @kim.tenant_id, user: user, email: user.email, status: "active")
    RoleAssignment.create!(account: acc, tenant_id: acc.tenant_id, role_key: "contributor",
                           scope_type: "workspace", scope_workspace_id: @ws.id)
    acc
  end

  test "(a) 작업실 grant 멤버는 두 루트 모두 가시 — 홈 카드 1개 + 진입 시 컨텍스트 트리 2루트" do
    sign_in_as(workspace_member)

    # 홈: 합본 작업실 카드(멤버는 실루트를 보므로 라벨=작업실명) · 타 작업실(레티놀 등) 부재.
    get root_path
    assert_response :success
    assert_match "합본 작업실", response.body
    assert_no_match "레티놀 3% 세럼", response.body

    # 진입: 컨텍스트 트리(메인 테이블)에 두 루트 + 각 리프가 모두 렌더 = 복수 루트 수용.
    get workspace_path(@ws)
    assert_response :success
    table_ids = css_select("table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
    [ @root_a, @root_b, @leaf_a, @leaf_b ].each do |p|
      assert_includes table_ids, p.id.to_s, "#{p.name}는 그 작업실 트리에 렌더(복수 루트)"
    end
  end

  test "(b) 비멤버(타 스코프 choi)는 합본 작업실을 보지 못한다 — 진입 303 · 홈 카드 부재" do
    sign_in_as(Account.find_by!(email: "choi@partner.example")) # CO0200만 스코프

    get workspace_path(@ws)
    assert_redirected_to root_path # 같은 테넌트·비가시 작업실 진입 → 303

    get root_path
    assert_no_match "합본 작업실", response.body
    assert_no_match "브랜드A", response.body
    assert_no_match "브랜드B", response.body
  end

  test "(c) tenant-wide(kim)는 두 루트를 카드 1개(제품 2)로 본다" do
    sign_in_as(@kim)
    get root_path
    assert_response :success
    assert_match "합본 작업실", response.body

    # 진입: 두 루트가 한 작업실 트리에 함께.
    get workspace_path(@ws)
    table_ids = css_select("table tbody tr[data-node-id]").map { |tr| tr["data-node-id"] }
    assert_includes table_ids, @root_a.id.to_s
    assert_includes table_ids, @root_b.id.to_s
  end

  test "(d) 작업실 멤버 로스터·요약은 workspace grant 계정을 포함한다" do
    member = workspace_member
    sign_in_as(@kim) # 관리자 — 작업실 페이지 멤버 요약
    get workspace_path(@ws)
    assert_response :success
    assert_match "합본멤버", response.body, "workspace grant 멤버는 작업실 멤버 요약에 표시"
  end
end
