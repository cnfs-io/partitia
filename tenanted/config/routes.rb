Rails.application.routes.draw do
  # Tenant subdomain present -> that tenant's Account settings (the singleton).
  # Declared FIRST: Rails matches top-down and the subdomain constraints make
  # these two root declarations mutually exclusive.
  constraints(subdomain: /.+/) do
    root "accounts#show", as: :tenant_root
  end

  # The tenant's self-service settings singleton (subdomain surface).
  resource :account, only: %i[ show edit update ]

  # Bare domain (no tenant subdomain) -> the global tenant registry list.
  constraints(subdomain: "") do
    root "tenants#index", as: :global_root
  end

  # Global-admin tenant registry CRUD (bare-domain surface).
  resources :tenants
end
