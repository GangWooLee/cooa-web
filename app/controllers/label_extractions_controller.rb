# 도안 텍스트 추출 PoC — "업로드 → 추출 → 사람 확정 → 스크리닝" 체인의 추출·확정 단계.
#  · GET  extraction : 첨부 PDF에서 성분/라벨 후보를 즉석 추출(무영속·순수 계산)해 체크박스 폼으로 렌더.
#  · POST extraction : 체크된 후보만 한 트랜잭션에서 ingredients/label_texts 행으로 생성(확정 시에만 쓰기).
# 후보는 저장하지 않는다(마이그레이션 0) — 후보 데이터는 폼 hidden 필드로 왕복하고, 확정된 행은 기존 계약
# 그대로 ScreeningService(@version.ingredients · label_texts blob)로 유입된다(스크리닝 무변경).
# 인가: 신규 verb 없이 upload_version? 재사용(도안에 콘텐츠를 다는 것은 버전 저작 권한과 동급).
class LabelExtractionsController < ApplicationController
  before_action :set_version

  # GET /versions/:id/extraction
  def show
    authorize @version, :upload_version?
    @candidates = extract_candidates
  end

  # POST /versions/:id/extraction
  def create
    authorize @version, :upload_version?
    created_ing = created_lbl = skipped = 0
    ActiveRecord::Base.transaction do
      pos = @version.ingredients.maximum(:position) || -1
      confirmed_ingredients.each do |c|
        # 중복 가드: 버전 내 동일 inci_name 성분은 건너뛴다(재확정 no-op).
        if @version.ingredients.exists?(inci_name: c[:inci_name])
          skipped += 1
        else
          @version.ingredients.create!(inci_name: c[:inci_name], inci_canonical: c[:inci_canonical], position: (pos += 1))
          created_ing += 1
        end
      end
      confirmed_labels.each do |c|
        # 중복 가드: 버전 내 동일 content 라벨은 건너뛴다.
        if @version.label_texts.exists?(content: c[:content])
          skipped += 1
        else
          @version.label_texts.create!(content: c[:content], text_type: "label", country: country, language: language)
          created_lbl += 1
        end
      end
    end
    redirect_to component_version_path(@version), notice: confirm_notice(created_ing, created_lbl, skipped)
  end

  private

  # 뷰는 브레드크럼(@product 조상 walk)과 country만 쓴다 — 담당자/멤버 렌더 없음이라 얕은 로드로 충분(무 N+1).
  def set_version
    @version   = ComponentVersion.find(params[:id])
    @component = @version.component
    @product   = @version.product
  end

  # 후보 추출 파이프라인(무영속). 실패/부재 상황을 status로 구분해 뷰가 각각 친절 문구를 렌더한다.
  def extract_candidates
    return { status: :no_artwork } unless @version.artwork.attached?
    return { status: :not_pdf }    unless @version.artwork_pdf?

    # 영속 첨부에서 추출 — blob.open이 로컬 임시파일로 내려받아 경로를 넘긴다(attachment_changes는 업로드 시점용).
    text = @version.artwork.blob.open { |f| PdfTextExtractor.extract(f.path) }
    return { status: :unavailable } if text == :unavailable # poppler 미설치
    return { status: :failed }      if text.nil?            # 손상·타임아웃

    parsed = DielineTextParser.parse(text)
    return { status: :empty } if parsed[:ingredients].empty? && parsed[:labels].empty?

    { status: :ok, ingredients: parsed[:ingredients], labels: parsed[:labels] }
  end

  # 체크된 후보만(ingredient_ids[]) + 그 hidden 데이터(ingredients[idx][...])를 짝지어 화이트리스트 통과분만 취한다.
  def confirmed_ingredients
    selected(:ingredient_ids, :ingredients).filter_map do |c|
      p = c.permit(:inci_name, :inci_canonical)
      name = p[:inci_name].to_s.strip
      next if name.blank?

      { inci_name: name, inci_canonical: (p[:inci_canonical].presence || name.upcase).to_s.strip }
    end
  end

  def confirmed_labels
    selected(:label_ids, :labels).filter_map do |c|
      content = c.permit(:content)[:content].to_s.strip
      content.presence && { content: content }
    end
  end

  # 체크박스 인덱스 배열(ids_key) ∩ hidden 데이터 해시(data_key) → 선택된 후보 Parameters 목록.
  def selected(ids_key, data_key)
    ids = Array(params[ids_key])
    data = params[data_key]
    return [] if ids.blank? || data.blank?

    ids.filter_map { |i| data[i].presence }
  end

  def country  = @product.country
  def language = country == "US" ? "en" : "ko"

  def confirm_notice(ing, lbl, skipped)
    parts = []
    parts << "성분 #{ing}건" if ing.positive?
    parts << "라벨 #{lbl}건" if lbl.positive?
    msg = parts.any? ? "도안에서 #{parts.join(' · ')}을 확정했습니다." : "확정할 항목을 선택하지 않았습니다."
    msg += " (중복 #{skipped}건 건너뜀)" if skipped.positive?
    msg
  end
end
