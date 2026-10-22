require "cnfs_support"

module CnfsTenanted
  class Engine < ::Rails::Engine
    # Declare the migration scopes this gem's topology needs, replacing
    # cnfs_support's generic default ({ primary: "db/migrate" }) wholesale — the
    # tenanted layer owns its scope names. Two scopes:
    #   :tenant -> db/migrate         (per-tenant migrations)
    #   :global -> db/global_migrate  (the shared Tenant registry)
    # Set at engine load, BEFORE the plugin is registered, so the value is in
    # place when set_migrations_paths_from walks migrations_paths_for on boot.
    CnfsSupport.migrations_paths_for.replace(
      tenant: "db/migrate",
      global: "db/global_migrate"
    )

    CnfsSupport.plugins << self

    # PROGRESSIVE ENHANCEMENT: teach cnfs_support's storage paths about tenancy.
    # cnfs_support::Storable builds paths through a swappable scope hook that
    # defaults to "no scope" (flat, single-tenant layout). When this gem is
    # present, every app IS multi-tenant, so we reassign the hook to the current
    # tenant handle. Each model's storage_path then gains a per-tenant segment
    # (<kind>/<handle>/<model_key>/…) with no change to cnfs_support and no
    # per-model wiring — the same inversion cnfs_support uses for migrations.
    #
    # The hook returns nil when there is no tenant context (e.g. a global-plane
    # or console call outside with_tenant); Storable then simply omits the scope
    # segment rather than raising, so unscoped callers still get a valid path.
    # Assigned at engine-load time (not an initializer) so it is in place before
    # any model touches storage during boot, mirroring migrations_paths_for.
    CnfsSupport.storage_scope = -> { ApplicationRecord.current_tenant }

    # Ensure each registered gem's models that are not explicit subclasses of GlobalRecord
    # are subtenant classes
    config.after_initialize do
      CnfsSupport.plugins.each do |plugin|
        next unless defined?(plugin.module_parent::ApplicationRecord)

        ar = plugin.module_parent::ApplicationRecord
        ar.subtenant_of("ApplicationRecord") if ar.respond_to?(:subtenant_of)
      end
    end

    # Defer Rack-level tenant selection to the TenantResolution concern.
    #
    # activerecord-tenanted auto-inserts its TenantSelector middleware (whenever
    # connection_class is set) and, by default, resolves a tenant by RAW
    # SUBDOMAIN and switches to a database of that name. Our databases are keyed
    # by the opaque, immutable HANDLE (ADR 0002 §5), and the subdomain->handle
    # step needs a Tenant lookup that a pure request resolver cannot do. So we
    # neutralize the middleware's resolver (it then runs every request
    # untenanted) and let CnfsTenanted::TenantResolution do the lookup, switch
    # to with_tenant(handle), and own the not-found seam.
    initializer "cnfs_tenanted.defer_tenant_selection" do |app|
      app.config.active_record_tenanted.tenant_resolver = ->(_request) { nil }
    end

    # Opt-in request-level tracing. Off by default; the host enables it with
    #   config.cnfs_tenanted.trace = true
    # which inserts the outer-request-span middleware (TelemetryMiddleware). The
    # flag must be set in config/application.rb or an environments file — early
    # enough that this engine initializer sees it (a config/initializers/*.rb
    # runs after engine initializers, too late to build the middleware stack).
    # Telemetry is still a no-op until the app installs cnfs_telemetry + an OTel
    # SDK, so this only decides whether the request span is emitted at all.
    config.cnfs_tenanted = ActiveSupport::OrderedOptions.new

    initializer "cnfs_tenanted.telemetry_middleware" do |app|
      if app.config.cnfs_tenanted.trace
        require "cnfs_tenanted/telemetry_middleware"
        app.middleware.use CnfsTenanted::TelemetryMiddleware
      end
    end

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
