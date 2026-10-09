require "cnfs_support"
require "turbo-rails"
require "stimulus-rails"
require "importmap-rails"
require "tailwindcss-rails"

module Iam
  class Engine < ::Rails::Engine
    isolate_namespace Iam

    # Register with cnfs_support so this engine's db/migrate joins the shared
    # migration-path registry the dummy app's database.yml reads
    # (CnfsSupport.migrations_paths[:primary]). Migrations are consumed via the
    # registry, never copied into spec/dummy. See ADR 0003 / plan 001 §2.3.
    CnfsSupport.plugins << self

    # Register identity seeding into cnfs_tenanted's provisioning hook — but only
    # when cnfs_tenanted is present (guarded: zero effect in single-tenant apps,
    # ADR 0001 §5). Registered once at after_initialize (not to_prepare, so no
    # duplicate entries on reload); the callable resolves Iam::TenantSeeder
    # lazily so a code reload never leaves a stale class reference in the
    # registry. iam does not depend on cnfs_tenanted — this is a one-way,
    # inverted touchpoint.
    config.after_initialize do
      if defined?(CnfsTenanted)
        CnfsTenanted.after_provision << ->(context) { Iam::TenantSeeder.call(context) }
      end
    end

    # Contribute console shortcuts/commands when cnfs_dev is present.
    # Only loads in a console session (never web/job processes).
    console do
      require_relative "pry_console"
      Iam::PryConsole.install!
    end
  end
end
