class DashboardController < ApplicationController
  # ① 데이터 관리 대시보드 — 제품 트리(펼침 행)
  def index
    load_dashboard_rows
  end
end
