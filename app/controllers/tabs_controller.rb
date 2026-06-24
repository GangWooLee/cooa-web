class TabsController < ApplicationController
  # 헤더 히스토리 탭 닫기 — 세션에서 키("p-1"/"v-5"/"s-5") 제거
  def destroy
    session[:open_tabs] = (session[:open_tabs] || []).reject { |key| key == params[:id] }
    redirect_back fallback_location: root_path
  end
end
