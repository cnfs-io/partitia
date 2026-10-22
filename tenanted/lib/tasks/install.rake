# frozen_string_literal: true

#
# Copy-in support for GLOBAL migrations.
#
# Rails auto-generates `partitia_tenanted:install:migrations` for this engine, but it
# only copies the engine's `db/migrate` (the TENANT scope) — the path Rails knows
# about. It has no concept of the GLOBAL scope (`db/global_migrate`), which the
# tenanted stack adds and activerecord-tenanted never contemplated (it assumes
# tenant migrations are authored in the host app).
#
# So this fills the matching gap for the global scope:
#
#   partitia:tenanted:install:global_migrations
#
# It walks Partitia::Support.migrations_paths[:global] — the absolute global-migration
# dirs collected at boot from EVERY registered engine (not just partitia-tenanted) —
# and copies them into the host's db/global_migrate. So a single run gathers the
# global migrations of any CNFS gem that ships them; no per-gem invocation.
#
# This is the copy-in counterpart to the hardcoded `migrations_paths:
# db/global_migrate` line the install generator writes. Hosts that instead
# uncomment the in-place ERB in database.yml don't need this task at all.

namespace :partitia do
  namespace :tenanted do
    namespace :install do
      desc "Copy global migrations from all CNFS engines into db/global_migrate"
      task global_migrations: :environment do
        # The collected, absolute global-migration source dirs (one per registered
        # engine that has a db/global_migrate). Populated by partitia-support at boot.
        sources = Partitia::Support.migrations_paths[:global].to_a

        if sources.empty?
          puts "No global migrations registered — nothing to copy."
          next
        end

        # Destination scope subdir in the host app.
        destination = Rails.root.join(Partitia::Support.migrations_paths_for.fetch(:global, "db/global_migrate"))
        FileUtils.mkdir_p(destination)

        # ActiveRecord::Migration.copy(destination, { scope => source_dir })
        # (Rails 8.1): for each source dir it rewrites the version to a fresh
        # timestamp, writes "#{version}_#{name}.#{scope}.rb" into destination, and
        # prepends "# This migration comes from #{scope}". It dedups by migration
        # NAME against what's already in destination, so re-runs are idempotent —
        # already-copied global migrations are skipped, not duplicated.
        #
        # `scope` is user-visible (filename suffix + comment), so we label each
        # source by its engine dir name. The source dir is
        # <engine_root>/db/global_migrate, so two parents up is the engine dir.
        # NOTE: value is a bare dir string, NOT an array — copy passes it straight
        # to MigrationContext.new.
        source_map = sources.each_with_object({}) do |dir, memo|
          scope = Pathname.new(dir).parent.parent.basename.to_s
          memo[scope] = dir
        end

        copied = ActiveRecord::Migration.copy(destination, source_map)

        rel = destination.relative_path_from(Rails.root)
        if copied.empty?
          puts "Global migrations already present in #{rel} — nothing to copy."
        else
          puts "Copied #{copied.size} global migration(s) into #{rel}:"
          copied.each { |m| puts "  #{File.basename(m.filename)}" }
        end
      end
    end
  end
end
