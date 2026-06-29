require "cnfs_support/tenant_migrations"

module CnfsTenanted
  class Engine < ::Rails::Engine
    # Register this engine's tenant migrations with the CNFS registry at
    # gem-load time (i.e. NOW, as this file is required during Bundler.require).
    #
    # This MUST run at load time rather than in an initializer: config/database.yml
    # is ERB-evaluated before initializers, and it reads
    # CnfsSupport::TenantMigrations.tenant_paths to build the tenanted DB's
    # migrations_paths. Registering here ensures our path is present by then.
    #
    # These migrations build each per-tenant database (the Account singleton,
    # plus whatever the host app adds). They are read in place, not copied into
    # the host — see the gem README on the phase-1/phase-2 migration strategy.
    CnfsSupport::TenantMigrations.register(
      File.expand_path("../../db/migrate", __dir__)
    )

    # Ship Tailwind-styled views; scaffolding/generators default accordingly.
    config.generators do |g|
      g.template_engine :tailwindcss
    end

    # Make the rake-task helper available when tasks load.
    rake_tasks do
      require "cnfs_tenanted/migration_status"
    end

    # Contribute tenant-aware Pry console helpers, but only when a console
    # session starts (never in web/job processes) and only if cnfs_dev is
    # present to host them. See CnfsTenanted::PryConsole.
    console do
      require "cnfs_tenanted/pry_console"
      CnfsTenanted::PryConsole.install!
    end
  end
end
