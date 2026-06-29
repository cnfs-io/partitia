# The global tenant registry. One row per tenant, living in the `global`
# database. Carries platform/admin-level configuration that the CNFS operator
# controls (as opposed to Account, which is the tenant's own self-service
# settings inside their tenant database).
#
# Top-level namespace by design (see GlobalRecord).
class Tenant < GlobalRecord
  validates :name, :subdomain, presence: true
  validates :subdomain, uniqueness: true

  # Provision the tenant's own database immediately after the registry row is
  # created, so visiting the subdomain works right away, then seed the tenant's
  # Account settings singleton with the tenant's name as a starting point. The
  # tenant can rename their Account independently afterward.
  after_create :provision_tenant

  private

  def provision_tenant
    create_tenant_database
    seed_account
  end

  # Idempotent: create_tenant raises if the tenant DB already exists, so guard
  # by checking the known tenant list first. (ApplicationRecord.tenants returns
  # the tenants currently on disk.)
  def create_tenant_database
    return if ApplicationRecord.tenants.include?(subdomain)

    ApplicationRecord.create_tenant(subdomain)
  end

  # Seed the per-tenant Account singleton inside the new tenant's database,
  # copying this Tenant's name across as the initial value.
  def seed_account
    ApplicationRecord.with_tenant(subdomain) do
      Account.instance(name: name)
    end
  end
end
