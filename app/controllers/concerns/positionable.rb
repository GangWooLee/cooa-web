# 형제 그룹(scope) 맨 아래 position 계산 — products/product_properties/components 공용.
module Positionable
  extend ActiveSupport::Concern

  private

  def next_position(scope) = (scope.maximum(:position) || -1) + 1
end
