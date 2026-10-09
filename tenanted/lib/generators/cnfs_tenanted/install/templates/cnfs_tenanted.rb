# cnfs_tenanted configuration.
#
# Tenant resolution strategy. The default reads the request subdomain
# (excluding "www"). Swap in another strategy or tune the exclusions here:
#
#   CnfsTenanted.tenant_resolver =
#     CnfsTenanted::Resolvers::Subdomain.new(excluded: %w[www admin api])
#   CnfsTenanted.tenant_resolver =
#     CnfsTenanted::Resolvers::HostHash.new("acme.com" => "acme")
#   CnfsTenanted.tenant_resolver =
#     CnfsTenanted::Resolvers::Header.new(header: "X-Tenant-Id", trusted: true)

# What to do when a subdomain resolves but no Tenant matches it. By default we
# redirect to the ejectable "unknown workspace" page, carrying the attempted
# name in flash so the page can show it. Edit
# app/views/tenant_not_found/unknown.html.erb (or eject it) to point people at
# your signup flow.
#
# Runs in controller context, so redirect_to / render are available. To go back
# to a plain 404, set this to nil. To handle it per-controller instead, leave
# this nil and define #tenant_not_found(name) in ApplicationController.
CnfsTenanted.tenant_not_found_handler = ->(tenant_name) do
  flash[:unknown_tenant] = tenant_name
  redirect_to tenant_unknown_path
end
