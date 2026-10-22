Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Tenant-context probes for request specs (behind TenantResolution).
  get "probe" => "probe#show"
  get "probe-override" => "probe_override#show"

  # --- Plan 004 integration ---------------------------------------------------
  # The auth broker, mounted per Plan 003.
  mount CnfsCognito::Engine => "/auth"

  # An operator route: authenticated (invite-only population) + one Pundit
  # policy with a fail-closed verify_authorized.
  get "dashboard" => "dashboard#show"

  # The end-user JIT entry point: records the :jit policy intent in the session,
  # then hands off to the broker login (the public /app namespace).
  get "app/login" => "app_login#create"

  # The platform (App Admin) login entry: pins the reserved DB for the OIDC
  # round-trip so resolution runs "as the platform".
  get "platform/login" => "platform_login#create"

  root "home#show"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
