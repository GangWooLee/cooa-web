Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ── COOA 데모 ──
  root "dashboard#index"
  get "/brands/:id", to: "dashboard#index", as: :brand        # 브랜드별 대시보드

  resources :products, only: [:show]                          # ② 제품 상세 허브

  resources :component_versions, only: [], path: "versions" do
    member do
      get  :screening,         to: "screenings#screening"          # ④ 인허가 스크리닝 화면
      post :run_screening,     to: "screenings#run_screening"      # 스크리닝 실행(룰엔진)
      post :approve_screening, to: "screenings#approve_screening"  # RA 승인
    end
    resources :feedbacks, only: [:create]                          # ③ 피드백 코멘트
  end

  # ③ 버전 비교: from(현 위치) vs to(비교 대상)
  get  "versions/:from_id/compare/:to_id",         to: "comparisons#show",    as: :comparison
  post "versions/:from_id/compare/:to_id/recheck", to: "comparisons#recheck", as: :recheck_comparison
end
