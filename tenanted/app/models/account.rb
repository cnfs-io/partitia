# The per-tenant settings singleton. Exactly one row exists in each tenant's
# own database (id is pinned to 1). This is the tenant's self-service
# configuration surface — editable by the tenant via accounts#show/edit on
# their subdomain — as opposed to Tenant, which holds operator/admin-level
# config in the global database.
#
# SINGLETON ENFORCEMENT (defense in depth):
#   1. Database: a CHECK (id = 1) constraint on the table (see the migration)
#      makes a second row physically impossible, regardless of how it's
#      attempted (console, race, buggy seed).
#   2. Model: SINGLETON_ID + .instance provide the only sanctioned accessor,
#      a find-or-create that always targets id 1.
#
# Because each tenant has its own database, "singleton per tenant" reduces to
# "singleton per database" — there is no tenant_id scoping to get wrong.
class Account < ApplicationRecord
  SINGLETON_ID = 1

  validates :name, presence: true

  # Guard against ever pointing at a non-singleton id at the model layer too.
  validates :id, inclusion: { in: [ SINGLETON_ID ] }

  class << self
    # The one and only Account row for the current tenant, created on first
    # access. Pass attributes (e.g. name:) used only when first creating it.
    #
    #   Account.instance                 # => the row (created if missing)
    #   Account.instance(name: "Acme")   # seeds name on creation
    def instance(**attributes)
      find_or_create_by!(id: SINGLETON_ID) do |account|
        account.assign_attributes(attributes)
        account.name ||= default_name
      end
    end

    private

    # Fallback name if none supplied at creation. Kept simple; the seeding path
    # in Tenant#after_create always supplies the tenant's name explicitly.
    def default_name
      "Account"
    end
  end

  # Singletons are never destroyed through normal flows; make that explicit.
  def destroy
    raise ActiveRecord::ReadOnlyRecord, "Account is a per-tenant singleton and cannot be destroyed"
  end
end
