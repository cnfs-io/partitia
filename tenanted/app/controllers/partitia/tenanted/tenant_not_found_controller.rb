module Partitia
  module Tenanted
    # The landing surface for a request whose subdomain (or other resolved tenant
    # name) does not match any registered Tenant. Served on the unknown
    # subdomain itself.
    #
    # This is where the TenantResolution concern's not-found seam points by
    # default (the install generator overrides ApplicationController#tenant_not_found
    # to redirect here). It exists so the out-of-the-box "unknown tenant"
    # experience is a real, editable page — point it at your signup flow, show a
    # "claim this subdomain" form, or redirect to the bare-domain registry.
    #
    # The host app gets a thin subclass via the install generator:
    #   class TenantNotFoundController < Partitia::Tenanted::TenantNotFoundController; end
    # Customize by overriding #unknown (call super or replace) and/or ejecting
    # the view with: bin/rails generate partitia:tenanted:views tenant_not_found
    class TenantNotFoundController < ::ApplicationController
      # The not-found seam's target: resolving the (unknown) tenant here again
      # would send the request back to this page, a redirect loop.
      skip_around_action :switch_tenant, raise: false

      # The resolved-but-unknown tenant name, surfaced to the view. Set by the
      # not-found seam via flash so it survives the redirect; falls back to the
      # request subdomain for direct visits.
      def unknown
        @tenant_name = flash[:unknown_tenant] || request.subdomain
        render status: :not_found
      end
    end
  end
end
