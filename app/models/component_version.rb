class ComponentVersion < ApplicationRecord
  include TenantScoped
  # 실무 포장 아트워크는 대개 PDF. 이미지와 공존(전환기·기존 데이터 보존) — 뷰어가 content_type로 분기.
  IMAGE_TYPES   = %w[image/png image/jpeg image/webp].freeze
  PDF_TYPE      = "application/pdf".freeze
  ARTWORK_TYPES = (IMAGE_TYPES + [ PDF_TYPE ]).freeze
  ARTWORK_MAX_BYTES = 30.megabytes # PDF는 이미지보다 큼(벡터·다중 요소)

  belongs_to :component
  belongs_to :created_by, class_name: "User", optional: true

  has_many :ingredients, -> { order(:position, :id) }, dependent: :destroy
  has_many :label_texts, dependent: :destroy
  has_many :annotations, -> { order(:seq, :position) }, dependent: :destroy
  has_many :screening_runs, dependent: :destroy
  has_many :approval_requests, dependent: :destroy # 리뷰는 버전에 앵커(리프레임 후속)

  # 업로드 아트워크(정적 에셋 image_name과 공존 — 렌더는 ui_helper#artwork_src가 분기).
  # :thumb = 미니맵·필름스트립용 래스터(PDF는 poppler preview 경유). preprocessed — 업로드 커밋 후
  # 백그라운드 잡이 선생성해 첫 뷰어 GET이 요청 스레드에서 pdftoppm+vips를 돌리지 않게(PERF-2).
  has_one_attached :artwork do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 2000, 2000 ], preprocessed: true
  end

  # 신규 버전 추가 시에만 파일 필수(컨트롤러가 플래그 set). 시드/수정엔 영향 없음.
  # 참고: 잘못된 형식 업로드는 422로 거부되나, ActiveStorage 표준 동작상 blob은 저장 시점에 기록되어
  #       미저장 레코드의 blob이 잠시 고아로 남을 수 있음(로컬 디스크 데모에서 무해 · 정기 purge로 정리).
  attr_accessor :require_artwork
  validates :artwork, presence: true, if: :require_artwork
  validate :artwork_format_and_size, if: -> { artwork.attached? }

  def vlabel = "v#{version_number}"
  def product = component.product
  def latest_screening = screening_runs.order(:created_at, :id).last # id 동률 보정(결정성)

  # 뷰어/썸네일 분기용 — PDF는 클라 PDF.js 캔버스, 이미지는 <img>.
  def artwork_pdf? = artwork.attached? && artwork.content_type == PDF_TYPE

  private

  def artwork_format_and_size
    unless ARTWORK_TYPES.include?(artwork.content_type)
      errors.add(:artwork, "는 PDF 또는 PNG·JPG·WEBP 파일이어야 합니다")
      return
    end
    if artwork.byte_size.to_i > ARTWORK_MAX_BYTES
      errors.add(:artwork, "크기는 30MB 이하여야 합니다")
      return
    end
    probe_pdf_openable if artwork.content_type == PDF_TYPE
  end

  # 업로드 시점 PDF 개봉 검사(SEC-2/F5 상류 차단): 손상·암호화·초대형 MediaBox를 422로 거부 —
  # 통과시켰다간 뷰어 빈화면(sticky notice)·preview 500·서버 pdftoppm 자원고갈로 하류에서 터진다.
  # 로컬 업로드 파일이 있을 때만(직접 blob attach 경로는 생략 — 시드/테스트 기존 동작 유지).
  def probe_pdf_openable
    src = attachment_changes["artwork"]&.attachable
    path = src.respond_to?(:tempfile) ? src.tempfile.path : (src.respond_to?(:path) ? src.path : nil)
    return if path.blank?
    result = PdfProbe.check(path)
    errors.add(:artwork, "— #{result.error}") unless result.ok
  end
end
