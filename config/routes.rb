Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # 規約系の3ページ（Threadsのアプリ審査で提出するURL）
  get "privacy" => "legal#privacy", as: :privacy
  get "terms" => "legal#terms", as: :terms
  get "data-deletion" => "legal#data_deletion", as: :data_deletion

  # 診断LP（指示7）ができたら root は diagnosis#index に差し替える
  root "legal#home"
end
