# Tenanted-lifecycle helpers for specs that touch real tenant databases.
#
# RSpec does not get activerecord-tenanted's Minitest genesis integration, so we
# provision and tear down tenant databases ourselves. Every example starts from
# a clean slate: no Tenant rows, no tenant DBs on disk, and all CnfsTenanted
# inversion slots reset to their defaults.
module TenancyHelpers
  # Create a registered tenant. Triggers provisioning (create_tenant + the
  # after_provision registry) via Tenant#after_create.
  def create_tenant!(subdomain:, name: subdomain.capitalize, owner_email: "owner@#{subdomain}.test")
    Tenant.create!(name: name, subdomain: subdomain, owner_email: owner_email)
  end

  # Destroy every tenant database file on disk (real tenants + the reserved
  # platform DB), swallowing errors so teardown is never the thing that fails.
  # Then PHYSICALLY remove any remaining per-tenant SQLite files: destroy_tenant
  # only sees "ready" tenants, but a crashed/partial provision can leave a file
  # that database_exist? still sees — and because the reserved handle is fixed
  # ("platform"), such a leftover would be silently reused and re-seeded.
  def destroy_all_tenant_databases!
    # Always include the reserved handle: its DB name is FIXED, so a cached
    # connection pool for it survives file deletion and would be reused against a
    # stale inode. destroy_tenant removes the pool (random-handle tenants get a
    # fresh pool each time, so only the fixed reserved handle needs this).
    handles = (ApplicationRecord.tenants + [ CnfsTenanted::RESERVED_HANDLE ]).uniq
    handles.each do |tenant|
      ApplicationRecord.destroy_tenant(tenant)
    rescue StandardError
      nil
    end
    Dir[Rails.root.join("storage", "test", "*.sqlite3")].each { |f| File.delete(f) rescue nil }
    # Flush any pooled connection still bound to a now-deleted tenant DB file
    # (destroy_tenant doesn't evict activerecord-tenanted's LRU pool cache; a
    # stale pool for the fixed reserved handle would otherwise be reused against
    # the deleted inode).
    ApplicationRecord.connection_handler.clear_all_connections! rescue nil
  end

  # Reset the module-level inversion slots so no example leaks configuration
  # into the next (order is randomized).
  def reset_cnfs_tenanted_slots!
    CnfsTenanted.after_provision.clear
    CnfsTenanted.tenant_not_found_handler = nil
    CnfsTenanted.platform_console_guard = nil
    CnfsTenanted.platform_table_prefixes = nil
  end
end

RSpec.configure do |config|
  config.include TenancyHelpers

  # Start every run from a clean slate: physically remove any per-tenant SQLite
  # files left by a previous (possibly crashed) run. This matters because RSpec
  # seeds the RNG, so Tenant handle generation is DETERMINISTIC within a seed —
  # a stale DB file whose handle a new tenant happens to regenerate would be
  # silently reused (create_tenant(if_not_exists: true)) and appear pre-seeded.
  # The global DB (storage/test.sqlite3) is left intact.
  config.before(:suite) do
    Dir[Rails.root.join("storage", "test", "*.sqlite3")].each { |f| File.delete(f) }
  end

  config.before do
    ApplicationRecord.current_tenant = nil
    destroy_all_tenant_databases!
    Tenant.delete_all
    reset_cnfs_tenanted_slots!
  end

  config.after do
    ApplicationRecord.current_tenant = nil
    destroy_all_tenant_databases!
    reset_cnfs_tenanted_slots!
  end
end
