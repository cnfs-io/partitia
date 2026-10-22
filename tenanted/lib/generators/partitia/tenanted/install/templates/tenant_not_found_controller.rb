# Landing page for an unknown workspace (a subdomain with no matching Tenant).
# Behavior lives in the engine; this thin subclass exists so routes resolve in
# the host namespace and so you can customize by overriding #unknown (call
# super or replace) and/or ejecting the view with:
#   bin/rails generate partitia:tenanted:views tenant_not_found
class TenantNotFoundController < Partitia::Tenanted::TenantNotFoundController
end
