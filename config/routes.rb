Rails.application.routes.draw do
  root "dashboard#show"

  get "history",   to: "history#show",    as: :history
  get "incidents", to: "incidents#index", as: :incidents

  resources :monitors, except: :index do
    post :check, on: :member
    resources :maintenance_windows, only: %i[ create destroy ]
  end

  resources :alert_channels, except: :show do
    post :test, on: :member
  end

  # Public: no login.
  get "status",  to: "status#show",  as: :status
  get "metrics", to: "metrics#show", as: :metrics

  # Health check for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check
end
