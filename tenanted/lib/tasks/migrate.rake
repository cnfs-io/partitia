# frozen_string_literal: true

#
# Migration tasks the tenanted layout needs and neither Rails nor
# activerecord-tenanted provides:
#
#   partitia:tenanted:migrate:status  — status of the global, platform and every
#                                       tenant database, tolerant of pending
#                                       migrations (ARTENANT=<handle> for one;
#                                       ARTENANT=global or =platform also work)
#   db:migrate:global                 — migrate only the :global database
#
# activerecord-tenanted already generates db:migrate:tenant, db:drop:tenant and
# db:reset:tenant from the config name.

namespace :partitia do
  namespace :tenanted do
    namespace :migrate do
      desc "Migration status of the global, platform and tenant databases (ARTENANT=<handle> for one)"
      task status: "db:load_config" do
        status = Partitia::Tenanted::MigrationStatus
        only = ENV["ARTENANT"].presence
        reports = status.reports(only: only)

        if only && reports.empty?
          known = [ "global", *status.tenant_names ]
          abort "No database #{only.inspect}. Known: #{known.join(', ')}"
        end

        status.print(reports)
      end
    end
  end
end

namespace :db do
  namespace :migrate do
    # activerecord-tenanted reports database_tasks? == false for the tenanted
    # :tenant config, so Rails sees a single tasked database (:global) and
    # never generates a per-name `db:migrate:global`. This defines it.
    desc "Migrate only the :global (non-tenanted) database"
    task global: :load_config do
      config = ActiveRecord::Base.configurations
        .configs_for(env_name: Rails.env, name: "global")

      abort "No :global database config for env #{Rails.env.inspect}" unless config

      verbose_was = ActiveRecord::Migration.verbose
      ActiveRecord::Migration.verbose = true

      ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |conn|
        pool = conn.pool
        if pool.migration_context.pending_migration_versions.present?
          pool.migration_context.migrate(nil)
          pool.schema_cache.clear!
        end
      end

      ActiveRecord::Tasks::DatabaseTasks.dump_schema(config) if ActiveRecord.dump_schema_after_migration
    ensure
      ActiveRecord::Migration.verbose = verbose_was unless verbose_was.nil?
    end
  end
end
