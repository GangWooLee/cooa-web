class ComponentVersionsController < ApplicationController
  # 특정 버전의 실제 파일 보기 (전체 페이지 — 드로어 아님)
  def show
    @version = ComponentVersion.includes(:created_by, :ingredients, :annotations,
                                         component: { product: {} }).find(params[:id])
    @component = @version.component
    @product   = @version.product
    @siblings  = @component.component_versions.sort_by(&:version_number)
    idx        = @siblings.index { |v| v.id == @version.id }
    @prev      = idx&.positive? ? @siblings[idx - 1] : nil
    @next      = idx && idx < @siblings.size - 1 ? @siblings[idx + 1] : nil
    track_tab("v", @version.id) # 헤더 히스토리 — 버전 파일 보기
  end

  def new
    @component = Component.find(params[:component_id])
    @version   = @component.component_versions.new(current: true)
  end

  def create
    @component = Component.find(params[:component_id])
    @version   = @component.component_versions.new(version_params)
    @version.label          = "[#{@component.product.code}]"
    @version.created_by     = current_user
    @version.require_artwork = true
    # with_lock으로 max(version_number) 읽기→insert 직렬화(동시 생성 시 번호 중복 방지)
    saved = false
    @component.with_lock do
      @version.version_number = (@component.component_versions.maximum(:version_number) || 0) + 1
      saved = @version.save
    end
    if saved
      enforce_single_current(@version)
      redirect_to component_version_path(@version), notice: "새 버전이 추가되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @version   = ComponentVersion.find(params[:id])
    @component = @version.component
  end

  def update
    @version   = ComponentVersion.find(params[:id])
    @component = @version.component
    if @version.update(version_params)
      enforce_single_current(@version)
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
