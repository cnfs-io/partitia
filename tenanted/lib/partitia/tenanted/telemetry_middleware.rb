require "cnfs_support/instrumentable"

module CnfsTenanted
  # Opt-in Rack middleware that opens the OUTER request span for a tenanted app,
  # so the whole request's wall-clock — and every span nested inside it (the
  # tenant switch, SQL, view rendering) — lives under one span.
  #
  # It resolves the tenant SUBDOMAIN here at the Rack edge. That is cheap, pure
  # request parsing with no database hit (CnfsTenanted.tenant_resolver), so it is
  # safe this early; it stamps tenant.subdomain onto the request span and onto
  # OTel baggage, so the value propagates from the very start of the request. The
  # HANDLE is deliberately NOT resolved here — subdomain -> handle needs a Tenant
  # lookup (a DB hit) that belongs to the controller layer;
  # CnfsTenanted::TenantResolution promotes tenant.handle onto the same span once
  # it resolves.
  #
  # Flat (CnfsTenanted::TelemetryMiddleware, not ::Middleware::Telemetry) on
  # purpose: CnfsSupport.component_tag takes everything-but-the-last segment, so a
  # three-level name would tag the component "cnfs_tenanted/middleware" and break
  # the "logs and traces share one identifier" rule. Two levels keeps it
  # "cnfs_tenanted" — event cnfs_tenanted.telemetry_middleware.request.
  #
  # This class emits nothing telemetry-specific: the span is an
  # ActiveSupport::Notifications event that cnfs_telemetry turns into a span
  # downstream — so tenanted keeps zero OTel dependency. Baggage is the one place
  # we touch OTel (it needs a Context attach/detach lifecycle around the
  # downstream call), reached only through a runtime `defined?(OpenTelemetry)`
  # probe, so there is still no load-time coupling.
  #
  # Not inserted by default. The host opts in with
  # `config.cnfs_tenanted.trace = true` (see CnfsTenanted::Engine), which is why
  # this middleware can assume it is wanted whenever it runs.
  class TelemetryMiddleware
    include CnfsSupport::Instrumentable

    def initialize(app)
      @app = app
    end

    def call(env)
      request   = ActionDispatch::Request.new(env)
      subdomain = resolve_subdomain(request)

      instrument(:request,
                 http_method: request.request_method,
                 path: request.path,
                 host: request.host,
                 subdomain: subdomain) do
        CnfsSupport::Instrumentable.set_span_context("tenant.subdomain" => subdomain)
        with_tenant_baggage(subdomain) { @app.call(env) }
      end
    end

    private

    # Pure parsing, never a DB hit. Telemetry must never take the app down, so
    # any resolver error degrades to "no subdomain" — the request just runs
    # without a tenant tag rather than 500ing at the Rack edge.
    def resolve_subdomain(request)
      CnfsTenanted.tenant_resolver.call(request)
    rescue StandardError
      nil
    end

    # Carry tenant.subdomain on OTel baggage for the duration of the downstream
    # call so it propagates to child spans. No-op without OTel or a subdomain.
    def with_tenant_baggage(subdomain)
      return yield if subdomain.nil? || !defined?(OpenTelemetry)

      context = OpenTelemetry::Baggage.set_value("tenant.subdomain", subdomain)
      token = OpenTelemetry::Context.attach(context)
      begin
        yield
      ensure
        OpenTelemetry::Context.detach(token)
      end
    end
  end
end
