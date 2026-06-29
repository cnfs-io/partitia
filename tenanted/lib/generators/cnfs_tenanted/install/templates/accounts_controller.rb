# The tenant's self-service Account settings singleton (subdomain surface).
# Behavior lives in the engine; this thin subclass exists so routes resolve in
# the host namespace and so you can customize by overriding actions here and/or
# ejecting the views with: bin/rails generate cnfs_tenanted:views accounts
class AccountsController < CnfsTenanted::AccountsController
end
