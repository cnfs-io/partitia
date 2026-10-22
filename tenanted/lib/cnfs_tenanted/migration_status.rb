module CnfsTenanted
  # Helpers for the db:migrate:status_primary / status_all rake tasks.
  #
  # Discovers tenants by listing their database files on disk (derived from the
  # %{tenant} template in the primary config's database path), and prints each
  # tenant's migration status by opening a temporary, unmanaged connection pool
  # against that tenant's database file. This deliberately avoids the
  # activerecord-tenanted runtime API, whose managed pools raise on tenants with
  # pending migrations — the exact case where status is most useful.
  module MigrationStatus
    module_function

    # The tenanted base config for the current environment's :tenant database.
    def tenant_base_config
      ActiveRecord::Base.configurations
        .configs_for(env_name: Rails.env, name: "tenant", include_hidden: true)
    end

    # Tenant names, derived from the tenant database files on disk.
    def tenant_names
      cfg  = tenant_base_config
      tmpl = cfg.configuration_hash[:database] # e.g. "storage/tenants/%{tenant}.sqlite3"

      glob_pattern  = tmpl.sub("%{tenant}", "*")
      regex_pattern = Regexp.new("\\A" + Regexp.escape(tmpl).sub('%\\{tenant\\}', "(.+)") + "\\z")

      Dir.glob(Rails.root.join(glob_pattern)).filter_map do |path|
        rel = Pathname.new(path).relative_path_from(Rails.root).to_s
        m = rel.match(regex_pattern)
        m && m[1]
      end.sort
    end

    # Open a temporary, unmanaged connection pool against ONE tenant's database
    # file and print its migration status. Pending migrations show as "down".
    def print(tenant)
      cfg       = tenant_base_config
      hash      = cfg.configuration_hash.dup
      db_path   = hash[:database].sub("%{tenant}", tenant)
      mig_paths = Array(hash[:migrations_paths]).presence || [ "db/migrate" ]

      tenant_hash = hash.merge(database: db_path, migrations_paths: mig_paths)
      db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
        Rails.env.to_s, "tenant_status_#{tenant}", tenant_hash
      )

      puts
      puts "database (tenant=#{tenant}): #{db_path}"
      puts
      puts " Status   Migration ID    Migration Name"
      puts "-" * 50

      ActiveRecord::PendingMigrationConnection.with_temporary_pool(db_config) do |pool|
        pool.migration_context.migrations_status.each do |status, version, name|
          puts "#{status.center(8)} #{version.ljust(15)} #{name}"
        end
      end
    end
  end
end
