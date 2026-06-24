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

  resources :products, only: [:show, :create, :update, :destroy] do  # ② 제품 트리 CRUD (생성=즉시·편집=인라인)
    patch :move, on: :member                                                      # 드래그앤드롭 트리 이동
    resources :components, only: [:create] do                                     # 구성요소 추가
      patch :reorder, on: :collection                                             # 드래그 순서변경
    end
    resources :product_properties, only: [:create, :update, :destroy], path: "properties"  # 커스텀 속성(Notion식)
  end

  # 구성요소 이름변경·삭제 + 새 버전 추가(구성요소 하위)
  resources :components, only: [:update, :destroy] do
    resources :component_versions, only: [:new, :create], path: "versions"
  end

  resources :component_versions, only: [:show, :edit, :update], path: "versions" do
    member do
      get  :screening,         to: "screenings#screening"          # ④ 인허가 스크리닝 화면
      post :run_screening,     to: "screenings#run_screening"      # 스크리닝 실행(룰엔진)
      post :approve_screening, to: "screenings#approve_screening"  # RA 승인
    end
    resources :annotations, only: [:create]                        # 바운딩박스 피드백 생성
  end

  resources :annotations, only: [] do
    member do
      patch :resolve   # 다음 버전 반영 확인
      patch :reopen
    end
    resources :comments, only: [:create], controller: "annotation_comments"
  end

  # ③ 버전 비교 (가치 라벨 없는 버전쌍 선택)
  get "versions/:from_id/compare/:to_id", to: "comparisons#show", as: :comparison

  # 상단 히스토리 탭 닫기(세션)
  delete "/tabs/:id", to: "tabs#destroy", as: :tab
end
