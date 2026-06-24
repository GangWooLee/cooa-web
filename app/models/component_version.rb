class ComponentVersion < ApplicationRecord
  ARTWORK_TYPES = %w[image/png image/jpeg image/webp].freeze
  ARTWORK_MAX_BYTES = 10.megabytes

  belongs_to :component
  belongs_to :created_by, class_name: "User", optional: true

  has_many :ingredients, -> { order(:position, :id) }, dependent: :destroy
  has_many :label_texts, dependent: :destroy
  has_many :annotations, -> { order(:seq, :position) }, dependent: :destroy
  has_many :screening_runs, dependent: :destroy

  # 업로드 아트워크(정적 에셋 image_name과 공존 — 렌더는 ui_helper#artwork_src가 분기)
  has_one_attached :artwork

  # 신규 버전 추가 시에만 파일 필수(컨트롤러가 플래그 set). 시드/수정엔 영향 없음.
  # 참고: 잘못된 형식 업로드는 422로 거부되나, ActiveStorage 표준 동작상 blob은 저장 시점에 기록되어
  #       미저장 레코드의 blob이 잠시 고아로 남을 수 있음(로컬 디스크 데모에서 무해 · 정기 purge로 정리).
  attr_accessor :require_artwork
  validates :artwork, presence: true, if: :require_artwork
  validate :artwork_format_and_size, if: -> { artwork.attached? }

  def vlabel = "v#{version_number}"
  def product = component.product
  def latest_screening = screening_runs.order(:created_at).last

  private

  def artwork_format_and_size
    unless ARTWORK_TYPES.include?(artwork.content_type)
      errors.add(:artwork, "는 PNG·JPG·WEBP 이미지여야 합니다")
    end
    if artwork.byte_size.to_i > ARTWORK_MAX_BYTES
      errors.add(:artwork, "크기는 10MB 이하여야 합니다")
    end
  end
end
