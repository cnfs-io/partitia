CnfsCognito::Engine.routes.draw do
  # Auth-code flow (Plan 003 WS3). Mounted by the host (the dummy mounts at
  # /auth), so these are /auth/login, /auth/callback, /auth/logout.
  get    "login",    to: "sessions#new"
  get    "callback", to: "sessions#callback"
  delete "logout",   to: "sessions#destroy"
end
