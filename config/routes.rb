Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations"
  }

  # Signed-in users land on their projects; visitors see the landing page.
  authenticated :user do
    root "projects#index", as: :authenticated_root
  end
  root "landing#show"

  # Single tools (sidebar's Create group): /create/speech, /create/image, ...
  scope "create/:kind", constraints: { kind: Regexp.union(CreationModels::KINDS) } do
    get "/", to: "creations#index", as: :creations
    post "/", to: "creations#create"
  end

  resources :projects, only: %i[index new create show] do
    resource :voice, only: %i[show create] do
      post :confirm
    end
    resource :scenes, only: %i[show create] do
      post :approve
      post :generate_suggested
      post :rewrite
    end
    resource :music, only: %i[show create update destroy], controller: "music" do
      post :upload
    end
    resource :render, only: %i[show create], controller: "renders"
    resource :publish, only: %i[show update], controller: "publish" do
      post :generate
      get :captions
    end
  end

  # A storyboard scene's narration: edit or delete it, or add an empty scene after it.
  resources :scenes, only: %i[update destroy], controller: "storyboard_scenes" do
    post :add_after, on: :member
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
