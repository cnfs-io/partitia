# frozen_string_literal: true

#
# The migration rake tasks the tenanted stack needs but neither Rails core nor
# activerecord-tenanted provides. Two gaps, filled here:
#
#   db:migrate:global          — migrate ONLY the plain :global database
#   db:migrate:status:global   — status for the :global database
#   db:migrate:status:tenant   — migration status across ALL tenant databases,
#                                tolerant of pending migrations
#
# What we do NOT define (the adapter already generates it, keyed off the config
# name, so renaming the config `primary` -> `tenant` gives these for free):
#   db:migrate:tenant, db:drop:tenant, db:reset:tenant  (+ aggregate wiring)
#
# All tasks depend on :load_config (not :environment) so merely loading them
# doesn't arm Rails' boot-time pending-migration check.

namespace :db do
  namespace :migrate do
    # --- :global database ----------------------------------------------------
    #
    # activerecord-tenanted reports database_tasks? == false for the tenanted
    # :tenant config, so Rails sees a single tasked database (:global) and
    # collapses everything onto the bare `db:migrate` — it never generates a
    # per-name `db:migrate:global`. This defines it, scoped to :global only.
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
      # the only database_tasks?-enabled config), so :global just delegates to
      # it. Defined for command symmetry with db:migrate:status:tenant.
      desc "Migration status for the :global (non-tenanted) database"
      task global: "db:migrate:status"

      # --- tenant databases --------------------------------------------------
      #
      # activerecord-tenanted ships db:migrate:tenant (migrate) but no matching
      # status task. This fills that gap and — crucially — works even when a
      # tenant has PENDING migrations, which is exactly when you most want
      # status (e.g. a pre-deploy check in prod).
      #
      # Why not ApplicationRecord.with_tenant? The gem deliberately raises
      # PendingMigrationError when it opens a managed pool for a tenant with
      # unapplied migrations — unusable for status-while-pending. Instead
      # MigrationStatus opens its OWN temporary, unmanaged pool per tenant
      # database file (the technique Rails core uses for pending checks),
      # bypassing the managed-pool guard.
      #
      # Usage:
      #   rails db:migrate:status:tenant                 # every tenant, looped
      #   ARTENANT=apple rails db:migrate:status:tenant  # one tenant
      desc "Migration status for tenant databases (set ARTENANT=<tenant> to filter to one)"
      task tenant: :load_config do
        tenants = Partitia::Tenanted::MigrationStatus.tenant_names

        if (filter = ENV["ARTENANT"].presence)
          unless tenants.include?(filter)
            abort "Tenant #{filter.inspect} does not exist. Known tenants: #{tenants.join(', ')}"
          end
          tenants = [ filter ]
        end

        if tenants.empty?
          puts "No tenants found."
          next
        end

        tenants.each do |t|
          Partitia::Tenanted::MigrationStatus.print(t)
          puts
        end
      end
    end
  end
end
