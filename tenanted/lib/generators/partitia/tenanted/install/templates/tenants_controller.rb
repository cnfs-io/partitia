# Global-admin tenant registry CRUD. Behavior lives in the engine; this thin
# subclass exists so routes resolve in the host namespace and so you can
# customize by overriding actions here (call super or replace) and/or ejecting
# the views with: bin/rails generate partitia:tenanted:views tenants
class TenantsController < Partitia::Tenanted::TenantsController
end
