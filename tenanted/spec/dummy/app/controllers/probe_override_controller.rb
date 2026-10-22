# Exercises the first layer of the not-found seam: a controller that overrides
# #tenant_not_found wins over the configured handler and the built-in 404.
class ProbeOverrideController < ProbeController
  private

  def tenant_not_found(tenant_name)
    render plain: "override: #{tenant_name}", status: :not_found
  end
end
