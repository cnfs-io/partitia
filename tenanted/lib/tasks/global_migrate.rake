# frozen_string_literal: true
#
# Scoped migration of the non-tenanted :global database.
#
# activerecord-tenanted reports database_tasks? == false for the tenanted
# :primary config, so Rails sees a single tasked database and collapses
# everything onto the bare `db:migrate` — it never generates a per-name
# `db:migrate:global` task. This defines it.
#
# Usage:
#   rails db:migrate:global         # migrate ONLY the global database
#   rails db:migrate:status:global  # status for the global database
#
# Companion to db:migrate:<tenant> (gem) and db:migrate:status:tenants (this gem).
# Depends on :load_config (not :environment) so it doesn't arm Rails' boot-time
# pending-migration check.

namespace :db do
  namespace :migrate do
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

    namespace :status do
      # The bare db:migrate:status already reports on the :global database (it's
      # the only database_tasks?-enabled config), so :global just delegates to it.
      # Defined for command symmetry with db:migrate:status:tenants.
      desc "Migration status for the :global (non-tenanted) database"
      task global: "db:migrate:status"
    end
  end
end
