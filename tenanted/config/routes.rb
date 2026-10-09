Rails.application.routes.draw do
  # The "unknown workspace" landing page. Outside the subdomain constraints
  # because the visitor is sitting on the unknown subdomain when the not-found
  # seam redirects them here. The TenantResolution concern points at this by
  # default (tenant_unknown_path / _url).
  get "tenant-unknown", to: "tenant_not_found#unknown", as: :tenant_unknown

  # Global-admin tenant registry CRUD (bare-domain surface). The host owns the
  # root routes on both planes (ADR 0003 §6); the gem contributes only the
  # tenant registry and the not-found seam.
  resources :tenants
end
