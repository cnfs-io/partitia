Rails.application.routes.draw do
  # Mount the broker. Login/callback/logout live under /auth (Plan 003 WS3).
  mount CnfsCognito::Engine => "/auth"

  get "up" => "rails/health#show", as: :rails_health_check

  # A landing/target for after_sign_in / after_sign_out redirects in specs.
  get "home" => "home#show"
  root "home#show"
end
