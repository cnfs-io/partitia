# A trivial tenant-context probe for request specs. Because it inherits the
# TenantResolution around_action from ApplicationController, hitting it on a
# tenant subdomain proves the request ran inside that tenant's DB context;
# hitting it on an unknown subdomain drives the not-found seam.
class ProbeController < ApplicationController
  def show
    render plain: "probe: #{ApplicationRecord.current_tenant}"
  end
end
