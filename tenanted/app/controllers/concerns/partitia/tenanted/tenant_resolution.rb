module Partitia
  module Tenanted
    # Resolves the current tenant from the request and runs the action inside
    # that tenant's database context. The "how do we read a tenant from the
    # request?" decision is delegated to a resolver (see Partitia::Tenanted::Resolvers)
    # so the strategy — subdomain, vanity host, edge header — is swappable
    # without touching this concern.
    #
    # A nil/blank resolution falls through untenanted (the bare-domain
    # registry/landing surface). A resolved-but-unknown tenant is routed through
    # the not-found seam (see #tenant_not_found below).
    #
    # The host app includes this in its ApplicationController (the install
    # generator injects the `include`):
    #
    #   class ApplicationController < ActionController::Base
    #     include Partitia::Tenanted::TenantResolution
    #   end
    #
    # To change strategy, set the resolver in an initializer:
    #
    #   # config/initializers/partitia_tenanted.rb
    #   Partitia::Tenanted.tenant_resolver =
    #     Partitia::Tenanted::Resolvers::Subdomain.new(excluded: %w[www admin api])
    #
    # Namespaced (Partitia::Tenanted::) because it is a mixin, not an app-level base
    # class — unlike Tenant/GlobalRecord, which are top-level by design.
    module TenantResolution
      extend ActiveSupport::Concern

      included do
        around_action :switch_tenant
      end

      private

      def switch_tenant(&block)
        tenant_name = Partitia::Tenanted.tenant_resolver.call(request)

        # The `outcome` payload key makes the three resolution paths distinct in a
        # trace: untenanted (blank), switched, or not_found. The handle is added
        # once known. The request's server span already has tenant.subdomain and
        # tenant.handle, from the Rack layer (Partitia::Tenanted.request_handle).
        instrument_tenant(:switch, subdomain: tenant_name) do |payload|
          if tenant_name.blank?
            payload[:outcome] = "untenanted"
            yield
          else
            # The resolver only parsed a subdomain/host/header value; look it up to
            # a Tenant to (a) confirm registration and (b) recover the immutable
            # routing key. The database is keyed by `handle`, never the mutable
            # subdomain (ADR 0002 §5 / ADR 0003 §5).
            begin
              tenant = Partitia::Tenanted::Tenant.find_by!(subdomain: tenant_name)
            rescue ActiveRecord::RecordNotFound
              # A resolved-but-unknown tenant is an expected outcome, not a span
              # error — record it and run the not-found seam inside the same span.
              payload[:outcome] = "not_found"
              next tenant_not_found(tenant_name)
            end

            payload[:outcome] = "switched"
            payload[:handle]  = tenant.handle
            ApplicationRecord.with_tenant(tenant.handle, &block)
          end
        end
      end

      # Emit under the gem's OWN component (partitia_tenanted.tenant_resolution.*)
      # rather than the host's ApplicationController: this is a mixin, so `self` is
      # the host controller and Partitia::Support::Instrumentable#instrument would compose
      # the event from the wrong class. `TenantResolution.name` resolves lexically
      # to Partitia::Tenanted::TenantResolution, so the component stays "partitia_tenanted".
      def instrument_tenant(verb, **payload, &block)
        name = Partitia::Support::Instrumentable.event_name(TenantResolution.name, verb)
        ActiveSupport::Notifications.instrument(name, **payload, &block)
      end

      # The not-found seam. Resolution order:
      #
      #   1. The host's own override of this method (define #tenant_not_found in
      #      ApplicationController or a controller) — the ergonomic path: use
      #      redirect_to / render with the full controller API.
      #   2. Partitia::Tenanted.tenant_not_found_handler, a configured callable run in
      #      controller context (instance_exec) so it too can redirect_to/render.
      #   3. The built-in default: a plain 404.
      #
      # Because this runs *inside* the around_action, returning without rendering
      # or redirecting means the tenanted action never executes — control does
      # not fall through to a tenant that doesn't exist. That is the safety rail:
      # the worst a misbehaving handler can do is produce a blank 200, never leak
      # into another tenant's context.
      #
      # The host generator (see install) overrides this to redirect to an
      # ejectable "unknown tenant" page, so the out-of-the-box experience is a
      # real, editable landing/signup surface rather than plain text.
      def tenant_not_found(tenant_name)
        handler = Partitia::Tenanted.tenant_not_found_handler
        if handler
          instance_exec(tenant_name, &handler)
        else
          render plain: "Tenant '#{tenant_name}' not found", status: :not_found
        end
      end
    end
  end
end
