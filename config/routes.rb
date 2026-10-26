Rails.application.routes.draw do
  root "projects#index"

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  resources :projects, only: %i[index new create show] do
    resource :script, only: %i[create update]
    resource :voice, only: %i[show create] do
      post :confirm
    end
    resource :scenes, only: :show
  end

  resources :voice_samples, only: :create

  get "up" => "rails/health#show", as: :rails_health_check
end
