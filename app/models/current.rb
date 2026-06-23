# 데모용 현재 사용자 컨텍스트 (고정 사용자 자동 로그인)
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
