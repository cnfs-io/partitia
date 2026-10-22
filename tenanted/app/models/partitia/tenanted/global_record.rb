# Base class for GLOBAL (non-tenanted) models — data shared across all tenants,
# such as the Tenant registry itself. Lives in the dedicated `global` database,
# separate from the per-tenant databases that ApplicationRecord connects to.
#
# Defined in the top-level namespace (not CnfsTenanted::) deliberately: this is
# foundational app infrastructure that host-app global models inherit from, the
# same way they inherit from ApplicationRecord. See the gem README.
class GlobalRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :global, reading: :global }
end
