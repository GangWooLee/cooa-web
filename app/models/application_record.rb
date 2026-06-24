class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # 국가 코드 ↔ 한글 표시 (규제 데이터는 코드, 화면은 한글)
  COUNTRY_LABELS = { "US" => "미국", "JP" => "일본", "CN" => "중국", "KR" => "한국" }.freeze
  def self.country_label(code) = COUNTRY_LABELS[code] || code

  # 자유입력 국가 정규화 — 알려진 코드/한글라벨은 코드로, 그 외엔 원문(공백 정리). nil/빈값은 nil.
  def self.normalize_country(value)
    v = value.to_s.strip
    return nil if v.blank?
    return v.upcase if COUNTRY_LABELS.key?(v.upcase)         # "us" → "US"
    COUNTRY_LABELS.key(v) || v                               # "미국" → "US", else 원문
  end
end
