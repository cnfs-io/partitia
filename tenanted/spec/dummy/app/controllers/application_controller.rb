class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Resolve the tenant from every request, exactly as the install generator
  # wires a real host. Runs the action inside the resolved tenant's DB context
  # (keyed by handle) or, for an unknown tenant, through the not-found seam.
  include CnfsTenanted::TenantResolution
end
