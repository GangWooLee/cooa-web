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

  # 로컬 account-picker 로그인 (dev/test; production은 Keycloak OIDC=Phase 2b). 비밀번호 없음.
  resource :session, only: [ :new, :create, :destroy ]
  # Keycloak OIDC (Phase 2b). The request phase /auth/openid_connect is handled by the OmniAuth middleware.
  match "/auth/:provider/callback", to: "sessions#omniauth_callback", via: %i[get post]
  get "/auth/failure", to: "sessions#auth_failure"

  resources :products, only: [ :show, :create, :update, :destroy ] do  # ② 제품 트리 CRUD (생성=즉시·편집=인라인)
    patch :move, on: :member                                                      # 드래그앤드롭 트리 이동
    resources :components, only: [ :create ] do                                     # 구성요소 추가
      patch :reorder, on: :collection                                             # 드래그 순서변경
    end
    resources :product_properties, only: [ :create, :update, :destroy ], path: "properties"  # 커스텀 속성(Notion식)
  end

  # 구성요소 이름변경·삭제 + 새 버전 추가(구성요소 하위)
  resources :components, only: [ :update, :destroy ] do
    resources :component_versions, only: [ :new, :create ], path: "versions"
  end

  resources :component_versions, only: [ :show, :edit, :update ], path: "versions" do
    member do
      get  :screening,     to: "screenings#screening"      # ④ 인허가 스크리닝 화면
      post :run_screening, to: "screenings#run_screening"  # 스크리닝 실행(룰엔진)
      # 승인은 Phase 3c에서 approval_requests로 이전(레거시 approve_screening 은퇴)
    end
    resources :annotations, only: [ :create ]                        # 바운딩박스 피드백 생성
  end

  resources :annotations, only: [] do
    member do
      patch :resolve   # 다음 버전 반영 확인
      patch :reopen
    end
    resources :comments, only: [ :create ], controller: "annotation_comments"
  end

  # ③ 버전 비교 (가치 라벨 없는 버전쌍 선택)
  get "versions/:from_id/compare/:to_id", to: "comparisons#show", as: :comparison

  # ④ 버전 리뷰(리프레임) — submit(create=리뷰 요청) / confirm(검토 확인). "고쳐야 함"은 피드백 채널.
  resources :approval_requests, only: [ :create ] do
    member do
      post :confirm
      post :claim   # 미배정 pending 리뷰 자기배정(적격 owner/approver)
    end
  end

  # "내게 요청된 리뷰" 수신함(내가 지정 리뷰어인 pending 요청)
  resources :reviews, only: [ :index ]

  # 조직 멤버십(Phase 3) — 로스터 / 초대 생성·회수 / 초대 랜딩(티켓 → 소셜 로그인 유도)
  resources :members, only: [ :index ]
  resources :invitations, only: [ :create, :destroy ]
  get "/invite/:token", to: "invitation_acceptances#show", as: :invite

  # 상단 히스토리 탭 닫기(세션)
  delete "/tabs/:id", to: "tabs#destroy", as: :tab
end
