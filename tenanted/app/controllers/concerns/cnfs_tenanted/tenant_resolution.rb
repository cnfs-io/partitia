module CnfsTenanted
  # Resolves the current tenant from the request subdomain and runs the action
  # inside that tenant's database context. Blank or "www" subdomains fall
  # through untenanted (the bare-domain registry/landing surface).
  #
  # The host app includes this in its ApplicationController (the install
  # generator injects the `include`):
  #
  #   class ApplicationController < ActionController::Base
  #     include CnfsTenanted::TenantResolution
  #   end
  #
  # Namespaced (CnfsTenanted::) because it is a mixin, not an app-level base
  # class — unlike Tenant/Account/GlobalRecord, which are top-level by design.
  module TenantResolution
    extend ActiveSupport::Concern

    included do
      around_action :switch_tenant
    end

    private

    def switch_tenant(&block)
      if request.subdomain.blank? || request.subdomain == "www"
        yield
      else
        tenant = Tenant.find_by!(subdomain: request.subdomain)
        ApplicationRecord.with_tenant(tenant.subdomain, &block)
      end
    rescue ActiveRecord::RecordNotFound
      render plain: "Tenant '#{request.subdomain}' not found", status: :not_found
    end
  end
end
