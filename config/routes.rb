Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

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

    resource :investor_collateral_deposit, only: :create, controller: "investor_collateral_deposits"

    resources :token_transfers, only: %i[new create]
    resource :investor_collateral_deposit, only: :create
    resource :settlement, only: %i[new create], controller: "settlements"
  end

  namespace :admin do
    resource :demo_reset, only: :create
    resource :market_rate, only: :update
    resource :chain_state, only: :update
  end

  if Rails.env.development? || Rails.env.test?
    namespace :dev do
      post "user_switch", to: "user_switches#create"
    end
  end
end
