require "activerecord-tenanted"
require "partitia/tenanted/version"
require "partitia/tenanted/resolvers"
require "partitia/tenanted/platform_scope_guard"
require "partitia/tenanted/engine"

# Partitia::Tenanted provides the multi-tenant layer for CNFS Rails apps, built on
# activerecord-tenanted (database-per-tenant). It supplies:
#
#   * GlobalRecord / Tenant   — the global tenant registry (shared DB)
#   * TenantResolution        — request -> tenant concern (delegates to Resolvers)
#   * Resolvers               — subdomain / host-hash / header strategies
#   * Tenant registry MVC     — provided by the engine, ejectable via generators
#   * tenant migration status — rake task (db:migrate:status:tenant)
#   * console helpers         — contributed to partitia-dev when present
#
# It owns the GLOBAL plane and the reserved PLATFORM plane (ADR 0003): tenant
# provisioning, the after_provision inversion hook, and the sanctioned
# `with_platform` entry point. It owns nothing INSIDE a tenanted database — the
# identity models live in the iam engine (ADR 0003 §6 ownership rule).
#
# Install into a host app with: bin/rails generate partitia:tenanted:install
module Partitia
  module Tenanted
    # The reserved handle whose database is the platform's own identity plane
    # (ADR 0003 §2). It is never a Tenant: no row, never resolves from a
    # subdomain, never enumerated. Tenant validates against it; the handle
    # generator never produces it; the Subdomain resolver excludes it.
    RESERVED_HANDLE = "platform"

    class Error < StandardError; end

    # Raised inside a `with_platform` block when SQL touches a tenanted table that
    # is not on the platform allowlist (ADR 0003 §2 behavioral mitigation).
    class PlatformScopeViolation < Error; end

    # The engine is not isolated (the host owns the tenant-registry routes and
    # subclasses the controllers), so the two things isolate_namespace would
    # provide are declared here: tables take the partitia_tenanted_ prefix
    # (partitia_tenanted_tenants), and model naming is relative to this module so
    # Partitia::Tenanted::Tenant keeps the `tenants` / `tenant` route and param keys.
    def self.table_name_prefix = "partitia_tenanted_"
    def self.use_relative_model_naming? = true

    # Deny is the default console decision: an unconfigured platform console is a
    # closed console (ADR 0003 §6 / Plan 001 WS5.4). Runs in controller context.
    DEFAULT_CONSOLE_GUARD = -> { head :forbidden }

    # The provisioning context passed to after_provision hooks for the PLATFORM
    # run. It satisfies the same duck type as a Tenant record — `#name` and
    # `#owner_email` — so identity seeding takes one code path across both planes
    # (ADR 0003 §2, Plan 002 Piece 5).
    PlatformContext = Struct.new(:owner_email) do
      def name
        "Platform"
      end
    end

    class << self
      attr_writer :tenant_resolver

      # A callable run in controller context (instance_exec) when a tenant name
      # resolved but no matching Tenant exists. Receives the tenant name; can
      # call redirect_to/render. Nil (the default) means "use the built-in 404".
      attr_accessor :tenant_not_found_handler

      attr_writer :platform_console_guard, :platform_table_prefixes

      # The resolver the TenantResolution concern uses to turn a request into a
      # tenant name (a subdomain/host/header value, later looked up to a handle).
      # Defaults to subdomain resolution; assign any callable to override.
      def tenant_resolver
        @tenant_resolver ||= Resolvers.default
      end

      # The ordered after_provision registry (ADR 0003 §6): callables run inside
      # the freshly provisioned database's tenant context, each receiving the
      # provisioning context (an object responding to #name and #owner_email — a
      # Tenant for tenants, a PlatformContext for the platform run). A raise
      # aborts provisioning. iam registers its identity seeder here.
      #
      #   Partitia::Tenanted.after_provision << Partitia::Iam::TenantSeeder
      def after_provision
        @after_provision ||= []
      end

      # The platform console's access decision, run in controller context
      # (instance_exec) as a before_action. Defaults to deny. The host wires it to
      # broker authentication + a platform Pundit policy.
      def platform_console_guard
        @platform_console_guard ||= DEFAULT_CONSOLE_GUARD
      end

      # Table-name prefixes whose tables may be touched inside `with_platform`.
      # Defaults to partitia_iam_ (identity only); AR internals are always allowed.
      def platform_table_prefixes
        @platform_table_prefixes ||= %w[partitia_iam_]
      end

      # Idempotently provision the reserved PLATFORM database (ADR 0003 §2). It
      # runs the same after_provision registry as tenant provisioning, so the
      # reserved DB is seeded exactly like a tenant DB (Account singleton + root
      # principal — the platform owner — with a bootstrap token).
      #
      # DB-file existence is the "already seeded?" signal (the same guard as
      # create_tenant). A platform DB that exists but was seeded only partway (a
      # crash mid-hook) is a crashed-provision state: delete the reserved DB file
      # and re-run to recover (acceptable pre-v1). No Tenant row is ever created.
      def provision_platform!(owner_email:)
        return if ApplicationRecord.tenant_exist?(RESERVED_HANDLE)

        run_provision(RESERVED_HANDLE, PlatformContext.new(owner_email), cleanup_on_failure: false)
      end

      # The sanctioned entry point into the reserved database (ADR 0003 §2).
      # Pins the reserved tenant context and, for the duration of the block,
      # installs the platform scope guard: any SQL touching a non-allowlisted
      # tenanted table raises PlatformScopeViolation.
      def with_platform(&block)
        ApplicationRecord.with_tenant(RESERVED_HANDLE) do
          PlatformScopeGuard.enforce(platform_table_prefixes, &block)
        end
      end

      # The tenant handles on disk, EXCLUDING the reserved platform handle.
      # (Raw ApplicationRecord.tenants includes the reserved handle — never
      # enumerate that directly for tenant-facing operations.)
      def tenant_handles
        ApplicationRecord.tenants - [ RESERVED_HANDLE ]
      end

      # Yield each real tenant's handle inside its own DB context, reserved
      # handle excluded.
      def each_tenant
        tenant_handles.each do |handle|
          ApplicationRecord.with_tenant(handle) { yield handle }
        end
      end

      # Create the database for `handle` (idempotent) then run the after_provision
      # registry inside its tenant context, passing `context` to each hook. A hook
      # raise aborts and re-raises.
      #
      # cleanup_on_failure: for TENANT provisioning (true), a hook failure drops
      # the freshly created tenant DB so no orphan survives the rolled-back Tenant
      # row (the row rolls back with the after_create transaction; the DB file is
      # a separate SQLite file outside it, so we drop it explicitly). For the
      # PLATFORM run (false), we leave the half-seeded DB for manual recovery.
      def run_provision(handle, context, cleanup_on_failure:)
        # A once-per-tenant span: DB creation + the after_provision hook chain
        # (identity seeding et al.) is slow and worth tracing. The event name is
        # composed by hand here — unlike a model, a top-level module method has no
        # class for Partitia::Support::Instrumentable to derive "partitia_tenanted" from — but
        # follows the same <component>.<subject>.<verb> convention so it traces
        # under the partitia_tenanted tracer. A hook raise marks the span errored and
        # re-raises, then the cleanup below runs.
        ActiveSupport::Notifications.instrument(
          "partitia_tenanted.provisioning.run",
          handle: handle, reserved: handle == RESERVED_HANDLE
        ) do |payload|
          ApplicationRecord.create_tenant(handle, if_not_exists: true)

          ApplicationRecord.with_tenant(handle) do
            after_provision.each { |hook| hook.call(context) }
          end
          payload[:hook_count] = after_provision.size
        end
      rescue StandardError
        if cleanup_on_failure && ApplicationRecord.tenant_exist?(handle)
          ApplicationRecord.destroy_tenant(handle)
        end
        raise
      end
    end
  end
end
