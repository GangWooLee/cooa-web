class TabsController < ApplicationController
  # 헤더 히스토리 탭 닫기 — 세션에서 제거
  def destroy
    session[:open_tabs] = (session[:open_tabs] || []).reject { |id| id == params[:id].to_i }
    redirect_back fallback_location: root_path
  end
end
