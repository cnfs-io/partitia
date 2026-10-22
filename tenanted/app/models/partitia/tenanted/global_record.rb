# Base class for GLOBAL (non-tenanted) models — data shared across all tenants,
# such as the Tenant registry itself. Lives in the dedicated `global` database,
# separate from the per-tenant databases that ApplicationRecord connects to.
#
# Namespaced under Partitia::Tenanted (no Partitia gem defines a top-level
# constant). Host-app global models inherit from it the same way they inherit
# from ApplicationRecord:
#
#   class Plan < Partitia::Tenanted::GlobalRecord; end
#
# The partitia_tenanted_ table prefix (Partitia::Tenanted.table_name_prefix)
# applies only to models inside the Partitia::Tenanted namespace; a host model
# like Plan keeps its plain table name.
module Partitia
  module Tenanted
    class GlobalRecord < ActiveRecord::Base
      self.abstract_class = true

      connects_to database: { writing: :global, reading: :global }
    end
  end
end
