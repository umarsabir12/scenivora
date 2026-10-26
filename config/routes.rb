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
    resource :scenes, only: %i[show create] do
      post :approve
    end
    resource :music, only: :show, controller: "music"
  end

  scope "scenes/:scene_id", as: "scene" do
    resources :images, only: :create, controller: "scene_images" do
      post :select, on: :member
    end
    post "search", to: "scene_images#search", as: :search
    delete "image", to: "scene_images#clear", as: :clear_image
    post "ai_image", to: "scene_images#generate", as: :ai_image
  end

  resources :voice_samples, only: :create

  get "up" => "rails/health#show", as: :rails_health_check
end
