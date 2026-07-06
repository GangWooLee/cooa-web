require "application_system_test_case"

# T3 self-serve onboarding — real-browser journey. A brand-new VERIFIED Google visitor names their first
# workspace, lands in it as the owner (with the invite affordance), and a SECOND independent visitor mints a
# fully separate org. OmniAuth test_mode is process-global → shared with the Capybara server thread; we drive
# the callback directly (the request-phase button is covered by unit/integration — here we prove the
# onboarding SCREEN + atomic result render and work end-to-end in a browser).
class OnboardingJourneyTest < ApplicationSystemTestCase
  setup { OmniAuth.config.test_mode = true }

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "a new verified Google visitor self-onboards, lands in an owner workspace, and a 2nd visitor is isolated" do
    # ── visitor 1: unknown verified identity → onboarding screen → first workspace ────────────────
    onboard_via_google(uid: "g-sys-founder", email: "founder@sysco.example", name: "창업자", workspace: "레티놀 라인")
    assert_text "환영합니다", wait: 6                      # signed in as the new owner (flash)
    assert_text "레티놀 라인"                               # the new (empty) workspace, by its name (D2 header title)
    assert_selector "summary[aria-label='멤버 초대·관리']"  # owner affordance (D2 popover trigger·접근 이름=aria-label)

    # ── visitor 2: a different identity mints a COMPLETELY separate org ───────────────────────────
    onboard_via_google(uid: "g-sys-second", email: "second@other.example", name: "제2", workspace: "비타민C 라인")
    assert_text "환영합니다", wait: 6
    assert_text "비타민C 라인"

    # ── the two signups are distinct at the data floor (separate tenants, one workspace each) ──────
    a = Account.find_by!(idp_subject: "g-sys-founder")
    b = Account.find_by!(idp_subject: "g-sys-second")
    refute_equal a.tenant_id, b.tenant_id, "each self-serve signup mints its own tenant"
    assert_equal [ "레티놀 라인" ],  Workspace.where(tenant_id: a.tenant_id).pluck(:name)
    assert_equal [ "비타민C 라인" ], Workspace.where(tenant_id: b.tenant_id).pluck(:name)
    assert_equal 1, RoleAssignment.where(tenant_id: a.tenant_id, role_key: "owner").count
    assert_equal 1, RoleAssignment.where(tenant_id: b.tenant_id, role_key: "owner").count
  end

  private

  # Set the mock verified identity, drive the OAuth callback (→ onboarding screen), name the workspace, submit.
  def onboard_via_google(uid:, email:, name:, workspace:)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: { email: email, name: name },
      extra: { raw_info: { email_verified: true } }
    )
    visit "/auth/google_oauth2/callback"
    assert_text "첫 작업실 이름을 지어주세요", wait: 6
    fill_in "workspace_name", with: workspace
    click_button "작업실 만들고 시작하기"
  end
end
