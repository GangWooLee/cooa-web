# 계정 설정(셀프 서비스). 3섹션: 프로필 편집(이름·아바타 색·직무 — 전부 tenant-scoped accounts 컬럼) ·
# 계정 정보 읽기(로그인 이메일·방식·소속 조직) · 보안(모든 기기 로그아웃 = token_version bump).
#
# 보안 불변식: 절대 params id로 계정/유저를 조회하지 않는다 — 항상 current_account 자기 자신만 갱신.
# 그래서 BOLA 표면이 없다. 전역 users 테이블은 런타임 UPDATE 잠금(cooa.rake PERSON_TABLES)이라 편집
# 필드는 전부 accounts(이미 RLS+full DML)에 둔다. ProfilePolicy가 record==본인 계정을 명시 인가.
class SettingsController < ApplicationController
  def show
    authorize current_account, policy_class: ProfilePolicy
    load_view
  end

  def update
    authorize current_account, policy_class: ProfilePolicy
    if current_account.update(profile_params)
      redirect_to settings_path, notice: "프로필이 저장되었습니다."
    else
      flash.now[:alert] = current_account.errors.full_messages.to_sentence.presence || "저장하지 못했습니다."
      load_view
      render :show, status: :unprocessable_entity
    end
  end

  # 모든 기기에서 로그아웃 — 현재 세션 포함 전 세션 무효화(매요청 token_version 재검증, ADR-003 §3.3).
  def sign_out_all
    authorize current_account, policy_class: ProfilePolicy
    current_account.bump_token_version!
    reset_session
    redirect_to new_session_path, notice: "모든 기기에서 로그아웃되었습니다.", status: :see_other
  end

  private

  # current_organization은 뷰 헬퍼가 아니라 컨트롤러 private → 뷰용으로 인스턴스 변수에 담는다.
  def load_view
    @account = current_account
    @organization = current_organization
  end

  # 셀프 프로필만: accounts 표시 선호 3필드. users(전역 person)는 건드리지 않는다.
  def profile_params
    params.require(:account).permit(:display_name, :avatar_color, :job_title)
  end
end
