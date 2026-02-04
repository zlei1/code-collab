Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "rooms#index"

  get "/signup", to: "users#new"
  post "/signup", to: "users#create"

  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  get "/rooms", to: "rooms#index", as: :rooms
  get "/rooms/new", to: "rooms#new", as: :new_room
  post "/rooms", to: "rooms#create"
  get "/rooms/:slug", to: "rooms#show", as: :room
  patch "/rooms/:slug", to: "rooms#update"
  match "/rooms/:slug/join", to: "rooms#join", via: [ :get, :post ], as: :join_room

  get "/rooms/:slug/files", to: "room_files#index"
  get "/rooms/:slug/files/*path", to: "room_files#show"
  post "/rooms/:slug/run", to: "room_runs#create"
end
