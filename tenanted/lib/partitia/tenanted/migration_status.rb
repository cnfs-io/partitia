module Partitia
  module Tenanted
    # Migration status of every database the tenanted layout has: the global
    # database, the reserved platform database and each tenant database
    # (`bin/rails partitia:tenanted:migrate:status`). activerecord-tenanted ships
    # db:migrate:tenant but no status task.
    #
    # Each database is read through a temporary, unmanaged connection pool. The
    # activerecord-tenanted runtime API (with_tenant) is deliberately avoided: its
    # managed pools raise PendingMigrationError on a tenant with pending
    # migrations, the case where status matters most.
    module MigrationStatus
      HEADER = " Status   Migration ID    Migration Name".freeze

      # One database's status: rows are [status, version, name], status "up" or
      # "down" (pending). rows is nil when the database does not exist yet.
      Report = Struct.new(:label, :database, :rows) do
        def pending
          rows.to_a.count { |status, _, _| status == "down" }
        end
      end

      module_function

      def global_config
        ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "global")
      end

      # The tenanted base config (database template with %{tenant}).
      def tenant_base_config
        ActiveRecord::Base.configurations
          .configs_for(env_name: Rails.env, name: "tenant", include_hidden: true)
      end

      # Every tenant database on disk, the reserved platform database included.
      def tenant_names
        tenant_base_config&.tenants.to_a.sort
      end

      # Reports for the global database, the platform database and each tenant,
      # in that order. `only` limits them to one: "global" or a tenant handle
      # ("platform" for the reserved database).
      def reports(only: nil)
        names = tenant_names
        platform = names.delete(RESERVED_HANDLE)
        subdomains = tenant_subdomains

        databases = []
        databases << [ "global", "global", global_config ] if global_config
        databases << [ RESERVED_HANDLE, "platform (reserved)", tenant_config(platform) ] if platform
        names.each do |handle|
          label = subdomains[handle] ? "tenant #{handle} (#{subdomains[handle]})" : "tenant #{handle}"
          databases << [ handle, label, tenant_config(handle) ]
        end
        databases.select! { |key, _, _| key == only } if only

        databases.map { |_, label, config| report(label, config) }
      end

      def report(label, db_config)
        Report.new(label, db_config.database, migrations_status(db_config))
      end

      # [[status, version, name], ...] or nil when the database doesn't exist.
      def migrations_status(db_config)
        return nil if sqlite_file_missing?(db_config)

        ActiveRecord::PendingMigrationConnection.with_temporary_pool(db_config) do |pool|
          context = pool.migration_context
          if pool.schema_migration.table_exists?
            context.migrations_status
          else # a database nothing has migrated yet: everything is pending
            context.migrations.map { |m| [ "down", format("%.3d", m.version), m.name.underscore.humanize ] }
          end
        end
      rescue ActiveRecord::NoDatabaseError
        nil
      end

      def print(reports, io: $stdout)
        reports.each do |report|
          io.puts
          io.puts "#{report.label}: #{report.database}"
          io.puts
          if report.rows.nil? || report.rows.empty?
            io.puts(report.rows ? "  (no migrations)" : "  (database not created)")
            next
          end
          io.puts HEADER
          io.puts "-" * 50
          report.rows.each do |status, version, name|
            io.puts "#{status.center(8)}  #{version.ljust(14)}  #{name}"
          end
        end

        io.puts
        io.puts summary(reports)
      end

      def summary(reports)
        pending = reports.select { |r| r.pending.positive? }
        missing = reports.select { |r| r.rows.nil? }
        parts = [ "#{reports.size} #{reports.size == 1 ? 'database' : 'databases'}" ]
        parts << if pending.empty?
          "none pending"
        else
          "pending: " + pending.map { |r| "#{r.label} (#{r.pending})" }.join(", ")
        end
        parts << "not created: #{missing.map(&:label).join(', ')}" if missing.any?
        parts.join("; ")
      end

      # A plain (unmanaged) config for one tenant database.
      def tenant_config(handle)
        hash = tenant_base_config.new_tenant_config(handle).configuration_hash
          .except(:tenanted, :tenant, :tenanted_config_name)
        ActiveRecord::DatabaseConfigurations::HashConfig.new(Rails.env.to_s, "tenant_status_#{handle}", hash)
      end

      # handle => subdomain from the registry, or {} if it can't be read yet
      # (global database missing or not migrated).
      def tenant_subdomains
        Tenant.pluck(:handle, :subdomain).to_h
      rescue ActiveRecord::ActiveRecordError
        {}
      end

      # SQLite creates a missing file on connect; a status check must not.
      def sqlite_file_missing?(db_config)
        return false unless db_config.adapter.to_s.start_with?("sqlite")

        path = db_config.database.to_s
        return false if path.start_with?("file:") || path == ":memory:"

        !File.exist?(File.expand_path(path, Rails.root))
      end
    end
  end
end
