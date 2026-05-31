Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[new create destroy]
  get "login", to: "sessions#new"
  delete "logout", to: "sessions#destroy"

  root "dashboard#show"

  resources :budgets, only: %i[index show new create] do
    member do
      post :activate
    end

    resources :token_transfers, only: %i[new create]
    resource :settlement, only: %i[new create], controller: "settlements"
  end

  namespace :admin do
    resource :demo_reset, only: :create
    resource :market_rate, only: :update
  end

  if Rails.env.development?
    namespace :dev do
      post "user_switch", to: "user_switches#create"
    end
  end
end
