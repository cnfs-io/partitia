module Partitia
  module Tenanted
    # Request -> tenant-name resolution strategies.
    #
    # Each resolver is a plain callable satisfying the contract that
    # activerecord-tenanted's `tenant_resolver` expects:
    #
    #     call(request) -> String (tenant name) | nil (run untenanted)
    #
    # `request` is an ActionDispatch::Request (or anything API-compatible:
    # `#host`, `#subdomain`, `#get_header`). Returning nil/blank means "no tenant
    # for this request" — the caller runs the action/middleware untenanted (the
    # bare-domain registry/landing surface). Resolvers never switch tenants or
    # touch the database themselves; they only parse a name. Existence checking
    # and context switching belong to the caller (the TenantResolution concern,
    # the activerecord-tenanted TenantSelector middleware, or an Action Cable
    # connection).
    #
    # This mirrors the Apartment gem's "elevators", but collapsed to the lambda
    # contract activerecord-tenanted actually consumes: there is no Generic base
    # doing the switch — that role is already played by the caller.
    #
    # Strategies ship as classes (so they can carry config like exclusion lists)
    # but are interchangeable with bare lambdas. Assign one to the gem's resolver
    # slot in an initializer:
    #
    #     Rails.application.config.active_record_tenanted.tenant_resolver =
    #       Partitia::Tenanted::Resolvers::Subdomain.new(excluded: %w[www admin])
    #
    module Resolvers
      # Common helpers shared by the concrete resolvers. Subclasses implement
      # #call(request) and return a tenant name or nil.
      class Base
        # Normalize a parsed value into "a tenant name, or nil". Blank strings
        # become nil so callers have a single sentinel to branch on.
        def present_or_nil(value)
          value = value.to_s
          value.empty? ? nil : value
        end

        def call(_request)
          raise NotImplementedError, "#{self.class}#call must be implemented"
        end
      end
    end
  end
end
