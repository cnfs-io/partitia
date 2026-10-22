require "partitia/support"
require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"
require "tailwindcss-rails"

module Partitia
  module Iam
    class Engine < ::Rails::Engine
      isolate_namespace Partitia::Iam

      # Register with partitia-support so this engine's db/migrate joins the shared
      # migration-path registry the dummy app's database.yml reads
      # (Partitia::Support.migrations_paths[:primary]). Migrations are consumed via the
      # registry, never copied into spec/dummy. See ADR 0003 / plan 001 §2.3.
      Partitia::Support.plugins << self

      # Register identity seeding into partitia-tenanted's provisioning hook — but only
      # when partitia-tenanted is present (guarded: zero effect in single-tenant apps,
      # ADR 0001 §5). Registered once at after_initialize (not to_prepare, so no
      # duplicate entries on reload); the callable resolves Partitia::Iam::TenantSeeder
      # lazily so a code reload never leaves a stale class reference in the
      # registry. iam does not depend on partitia-tenanted — this is a one-way,
      # inverted touchpoint.
      config.after_initialize do
        if defined?(Partitia::Tenanted)
          Partitia::Tenanted.after_provision << ->(context) { Partitia::Iam::TenantSeeder.call(context) }
        end
      end

      # Contribute console shortcuts/commands when partitia-dev is present.
      # Only loads in a console session (never web/job processes).
      console do
        require_relative "pry_console"
        Partitia::Iam::PryConsole.install!
      end
    end
  end
end
