require "activerecord-tenanted"
require "cnfs_tenanted/version"
require "cnfs_tenanted/engine"

# CnfsTenanted provides the multi-tenant layer for CNFS Rails apps, built on
# activerecord-tenanted (database-per-tenant). It supplies:
#
#   * GlobalRecord / Tenant   — the global tenant registry (shared DB)
#   * Account                 — the per-tenant settings singleton (tenant DB)
#   * TenantResolution        — subdomain -> tenant request concern
#   * Tenant/Account MVC      — provided by the engine, ejectable via generators
#   * tenant migration status — rake task (db:migrate:status_all / _primary)
#   * console helpers         — contributed to cnfs_dev when present
#
# Install into a host app with: bin/rails generate cnfs_tenanted:install
module CnfsTenanted
  def self.global_migrations_paths
    @global_migrations_paths ||= []
  end

  def self.global_migrations
    global_migrations_paths.each_with_object([]) do |path, ary|
      ary.concat(Pathname.new(path).children.collect(&:to_s))
    end
  end
end
