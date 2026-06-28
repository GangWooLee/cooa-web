class DashboardController < ApplicationController
  # index lists via policy_scope (load_dashboard_rows) rather than authorize — verify the scope instead.
  skip_after_action :verify_authorized, only: :index
  after_action :verify_policy_scoped, only: :index

  # ① 데이터 관리 대시보드 — 제품 트리(펼침 행)
  def index
    load_dashboard_rows
  end
end
