Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "auth/login", to: "auth#login"
      get "auth/me", to: "auth#show"
      resource :dashboard, only: :show, controller: "dashboard"
      resource :market_rate, only: :show, controller: "market_rates"
      resource :reserve, only: :show, controller: "reserve" do
        post :sync, on: :member
      end
      resources :users, only: :index
      resources :transfers, only: :create
      resources :receive_requests, only: %i[create show], param: :id
      resources :deals, only: %i[index show create] do
        member do
          post :accept
        end
        resource :settlement, only: %i[show create], controller: "deals/settlements"
        resources :transfers, only: %i[index create], controller: "deals/transfers"
      end

      if Rails.env.development? || Rails.env.test?
        namespace :integration do
          post "demo_reset", to: "demo_resets#create"
          post "admin_fund_reserve", to: "admin_fund_reserves#create"
        end
      end
    end
  end

  resource :session, only: %i[new create destroy]
  get "login", to: "sessions#new"
  delete "logout", to: "sessions#destroy"

  root "dashboard#show"

  resource :token_transfer, only: %i[new create], controller: "token_transfers"
  resource :reserve_deposit, only: %i[new create]

  resources :budgets, only: %i[index show new create] do
    member do
      post :activate
    end

    resource :recovery_package, only: :show, controller: "budget_recovery_packages"

    resources :token_transfers, only: %i[new create]
    resource :settlement, only: %i[new create], controller: "settlements"
  end

  namespace :admin do
    resource :demo_reset, only: :create
    resource :market_rate, only: :update
    resource :chain_state, only: :update
    resource :reserve_deposit, only: :create, controller: "reserve_deposits"
  end

  if Rails.env.development? || Rails.env.test?
    namespace :dev do
      post "user_switch", to: "user_switches#create"
    end
  end
end
