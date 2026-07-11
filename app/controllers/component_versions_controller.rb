class ComponentVersionsController < ApplicationController
  # 특정 버전의 실제 파일 보기 (전체 페이지 — 드로어 아님)
  def show
    # created_by/pm.user는 저작권·담당자 뷰에서 표시 리졸버(account-우선)를 타므로 :account까지 프리로드(R5).
    @version = ComponentVersion.includes({ created_by: :account }, :ingredients, :annotations,
                                         component: { product: { product_members: { user: :account } } }).find(params[:id])
    authorize @version, :view_component_version?
    @component = @version.component
    @product   = @version.product
    @siblings  = @component.component_versions.sort_by(&:version_number)
    idx        = @siblings.index { |v| v.id == @version.id }
    @prev      = idx&.positive? ? @siblings[idx - 1] : nil
    @next      = idx && idx < @siblings.size - 1 ? @siblings[idx + 1] : nil
    # 어노테이션 created_by·댓글 author는 표시 리졸버(account-우선)를 타므로 :account까지 프리로드(R5).
    # 반영완료(resolved) 어노테이션은 뷰에서 resolved_in_version.vlabel을 읽으므로 그 버전도 프리로드
    # (누락 시 반영건당 component_versions 단건 N+1).
    @annotations = @version.annotations.ordered.includes({ created_by: :account }, :resolved_in_version, comments: { author: :account })
    # 버전 리뷰 패널: 리뷰는 버전에 앵커(스크리닝 비의존) — RA가 검토 중 스크리닝 수행. 스크리닝 링크는
    # 무조건 렌더되므로 latest_run 프리로드 불요(죽은 쿼리 제거).
    # 요청자(submitter)·지정 리뷰어·검토 확인 승인자(approval_steps.approver)는 리뷰 패널에서 표시 리졸버
    # (account-우선)를 타므로 :account까지 프리로드(R5). approver 누락 시 reviewed 버전 상세에서 승인자 신원의
    # users/accounts 단건 N+1 — 이 배치 프리로드로 흡수(presenter#confirmed_step는 인메모리 find로 전환).
    @approval_request = ApprovalRequest.includes({ requested_reviewers: :account }, { submitter: :account },
                                                 { approval_steps: { approver: :account } })
                                       .find_by(component_version_id: @version.id)
    @review = ReviewPanelPresenter.new(version: @version, request: @approval_request,
                                       open_feedback_count: @annotations.count(&:open?))
    TabHistory.track(session, "v", @version.id) # 헤더 히스토리 — 버전 파일 보기
  end

  def new
    @component = Component.find(params[:component_id])
    authorize @component, :upload_version?
    @version   = @component.component_versions.new(current: true)
  end

  def create
    @component = Component.find(params[:component_id])
    @version   = @component.component_versions.new(version_params)
    @version.label          = "[#{@component.product.code}]"
    @version.created_by     = current_user
    @version.require_artwork = true
    authorize @version, :upload_version?
    # with_lock으로 번호 채번 + current 단일성을 함께 직렬화(read-then-write 원자화)
    saved = false
    @component.with_lock do
      @version.version_number = (@component.component_versions.maximum(:version_number) || 0) + 1
      saved = @version.save
      enforce_single_current(@version) if saved
    end
    if saved
      redirect_to component_version_path(@version), notice: "새 버전이 추가되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @version   = ComponentVersion.find(params[:id])
    authorize @version, :upload_version?
    @component = @version.component
  end

  def update
    @version   = ComponentVersion.find(params[:id])
    authorize @version, :upload_version?
    @component = @version.component
    ok = false
    @component.with_lock do # current 단일성 read-then-write 원자화
      ok = @version.update(version_params)
      enforce_single_current(@version) if ok
    end
    if ok
      redirect_to component_version_path(@version), notice: "버전이 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # 빈 file 파라미터는 ActiveStorage가 무시 → 미첨부 시 기존 첨부 유지
  def version_params
    params.require(:component_version).permit(:change_reason, :current, :artwork)
  end

  # current 단일성: 정확히 하나의 현재 버전을 보장.
  #  - 이 버전이 current면 형제 해제
  #  - 아니면서 구성요소에 current가 하나도 없으면(예: 유일 current를 수정에서 해제) 최신 버전을 current로 복구
  def enforce_single_current(version)
    comp = version.component
    if version.current?
      comp.component_versions.where.not(id: version.id).update_all(current: false)
    elsif !comp.component_versions.exists?(current: true)
      comp.component_versions.order(:version_number).last&.update_column(:current, true)
    end
  end
end
