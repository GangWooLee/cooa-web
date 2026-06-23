class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # 국가 코드 ↔ 한글 표시 (규제 데이터는 코드, 화면은 한글)
  COUNTRY_LABELS = { "US" => "미국", "JP" => "일본", "CN" => "중국", "KR" => "한국" }.freeze
  def self.country_label(code) = COUNTRY_LABELS[code] || code
end
