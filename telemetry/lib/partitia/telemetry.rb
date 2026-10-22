require "opentelemetry"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require "partitia/support"

require "partitia/telemetry/version"
require "partitia/telemetry/config"
require "partitia/telemetry/subscriber"
require "partitia/telemetry/pry_console"
require "partitia/telemetry/railtie" if defined?(Rails::Railtie)

# Partitia::Telemetry bridges ActiveSupport::Notifications to OpenTelemetry.
#
# Every CNFS gem emits plain `ActiveSupport::Notifications` events via
# Partitia::Support::Instrumentable, under a `<component>.<class>.<verb>` naming
# convention where <component> is the underscored top-level module
# ("partitia_okf.bundle.create"). Those gems depend on nothing telemetry-related.
# This gem is the ONE place that knows about OpenTelemetry: it subscribes to the
# `partitia` family prefix and turns each event into a span on the OTel API tracer.
# It depends on `opentelemetry-api` only; until a host installs and configures
# the SDK, `OpenTelemetry.tracer_provider` is the API's no-op provider, so the
# whole bridge is free and harmless.
#
# Emit side (in any CNFS gem — no OTel dependency):
#
#   include Partitia::Support::Instrumentable
#   # ...
#   instrument(:create, bundle_id: id, path: path) do |payload|
#     # ... work whose duration becomes the span duration ...
#   end
#
# Bridge side (this gem, wired once by the host initializer):
#
#   Partitia::Telemetry.install!   # subscribes to the "partitia" event families
#
# The event name IS the span name. Its first dotted segment is the tracer's
# instrumentation-library name ("partitia_okf.bundle.create" => tracer "partitia_okf"),
# matching Partitia::Support::Logging's component tag so a gem's traces and logs align.
module Partitia
  module Telemetry
    class << self
      # The event-name prefixes the bridge subscribes to. Every CNFS gem's events
      # begin with an underscored-module component ("partitia_okf", "partitia_iam", ...),
      # so the single "partitia" prefix captures the whole family. Seeded from
      # Config#prefixes (PARTITIA_TELEMETRY_PREFIXES etc.); hosts may also append
      # their own via `Partitia::Telemetry.prefixes << "myapp"` before `install!`.
      def prefixes
        @prefixes ||= Config.prefix_list
      end

      # Forget the memoized prefixes (next access re-reads Config). For specs.
      def reset_prefixes!
        @prefixes = nil
      end

      # True once a real (SDK) tracer provider is registered. The API's default is
      # a ProxyTracerProvider that drops every span until the SDK replaces it.
      def sdk_configured?
        !OpenTelemetry.tracer_provider.instance_of?(OpenTelemetry::Internal::ProxyTracerProvider)
      end

      SDK_MISSING_MESSAGE =
        "OpenTelemetry SDK is not configured: partitia_* spans go nowhere. " \
        "Run `bin/rails g partitia:telemetry:install` (adds the SDK and " \
        "config/initializers/opentelemetry.rb).".freeze

      # Log SDK_MISSING_MESSAGE once per process when the gem is installed but
      # the SDK never was (ARCHITECTURE §7: not a silent no-op). Returns true when
      # it logged.
      def warn_if_sdk_unconfigured!(logger = default_logger)
        return false if @sdk_warned || sdk_configured?

        @sdk_warned = true
        logger&.warn(SDK_MISSING_MESSAGE)
        true
      end

      # For specs.
      def reset_sdk_warning!
        @sdk_warned = false
      end

      # Subscribe the bridge to every registered prefix. Idempotent: calling twice
      # does not double-subscribe. Returns self so a host initializer can chain.
      def install!
        return self if @installed

        @subscribers = prefixes.map { |prefix| Subscriber.subscribe(prefix) }
        @installed = true
        self
      end

      # Detach every subscriber the bridge installed. Primarily for test isolation
      # and for hosts that reconfigure prefixes at runtime.
      def uninstall!
        Array(@subscribers).each { |s| ActiveSupport::Notifications.unsubscribe(s) }
        @subscribers = nil
        @installed = false
        self
      end

      def installed?
        !!@installed
      end

      private

      # Tagged `[partitia_telemetry]`, through partitia-support's logging (§7).
      def default_logger
        Partitia::Support::Logging.build_for(name)
      end
    end
  end
end
