require "partitia/support"

module Partitia
  module Tenanted
    class Engine < ::Rails::Engine
      # Declare the migration scopes this gem's topology needs, replacing
      # partitia-support's generic default ({ primary: "db/migrate" }) wholesale — the
      # tenanted layer owns its scope names. Two scopes:
      #   :tenant -> db/migrate         (per-tenant migrations)
      #   :global -> db/global_migrate  (the shared Tenant registry)
      # Set at engine load, BEFORE the plugin is registered, so the value is in
      # place when set_migrations_paths_from walks migrations_paths_for on boot.
      Partitia::Support.migrations_paths_for.replace(
        tenant: "db/migrate",
        global: "db/global_migrate"
      )

      Partitia::Support.plugins << self

      # PROGRESSIVE ENHANCEMENT: teach partitia-support's storage paths about tenancy.
      # Partitia::Support::Storable builds paths through a swappable scope hook that
      # defaults to "no scope" (flat, single-tenant layout). When this gem is
      # present, every app IS multi-tenant, so we reassign the hook to the current
      # tenant handle. Each model's storage_path then gains a per-tenant segment
      # (<kind>/<handle>/<model_key>/…) with no change to partitia-support and no
      # per-model wiring — the same inversion partitia-support uses for migrations.
      #
      # The hook returns nil when there is no tenant context (e.g. a global-plane
      # or console call outside with_tenant); Storable then simply omits the scope
      # segment rather than raising, so unscoped callers still get a valid path.
      # Assigned at engine-load time (not an initializer) so it is in place before
      # any model touches storage during boot, mirroring migrations_paths_for.
      Partitia::Support.storage_scope = -> { ApplicationRecord.current_tenant }

      # Ensure each registered gem's models that are not explicit subclasses of GlobalRecord
      # are subtenant classes
      config.after_initialize do
        Partitia::Support.plugins.each do |plugin|
          next unless defined?(plugin.module_parent::ApplicationRecord)

          ar = plugin.module_parent::ApplicationRecord
          ar.subtenant_of("ApplicationRecord") if ar.respond_to?(:subtenant_of)
        end
      end

      # Select the tenant's database at the Rack layer, before any controller.
      #
      # activerecord-tenanted auto-inserts its TenantSelector middleware (whenever
      # connection_class is set). By default it resolves a tenant by RAW SUBDOMAIN;
      # our databases are keyed by the opaque, immutable HANDLE (ADR 0002 §5), so
      # the middleware gets Partitia::Tenanted.request_handle: the app's resolver
      # (subdomain by default), then the Tenant lookup to its handle. A blank or
      # unknown name is nil: the request runs untenanted and the TenantResolution
      # concern owns the not-found seam for the app's own routes.
      #
      # At the Rack layer because mounted engines don't inherit the host's
      # ApplicationController: cognito's OIDC callback (/auth/callback) has to run
      # in the tenant's database for the sign-in to land there (D6). The concern's
      # with_tenant on the same handle is then a no-op.
      initializer "partitia_tenanted.rack_tenant_selection" do |app|
        app.config.active_record_tenanted.tenant_resolver = ->(request) { Partitia::Tenanted.request_handle(request) }
      end

      # Opt-in request-level tracing. Off by default; the host enables it with
      #   config.partitia_tenanted.trace = true
      # which inserts the outer-request-span middleware (TelemetryMiddleware). The
      # flag must be set in config/application.rb or an environments file — early
      # enough that this engine initializer sees it (a config/initializers/*.rb
      # runs after engine initializers, too late to build the middleware stack).
      # Telemetry is still a no-op until the app installs partitia-telemetry + an OTel
      # SDK, so this only decides whether the request span is emitted at all.
      config.partitia_tenanted = ActiveSupport::OrderedOptions.new

      initializer "partitia_tenanted.telemetry_middleware" do |app|
        if app.config.partitia_tenanted.trace
          require "partitia/tenanted/telemetry_middleware"
          app.middleware.use Partitia::Tenanted::TelemetryMiddleware
        end
      end

      # Ship Tailwind-styled views; scaffolding/generators default accordingly.
      config.generators do |g|
        g.template_engine :tailwindcss
      end

      # Make the rake-task helper available when tasks load.
      rake_tasks do
        require "partitia/tenanted/migration_status"
      end

      # Contribute tenant-aware Pry console helpers, but only when a console
      # session starts (never in web/job processes) and only if partitia-dev is
      # present to host them. See Partitia::Tenanted::PryConsole.
      console do
        require "partitia/tenanted/pry_console"
        Partitia::Tenanted::PryConsole.install!
      end
    end
  end
end
