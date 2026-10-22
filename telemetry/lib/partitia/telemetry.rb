require "opentelemetry"
require "active_support/isolated_execution_state"
require "active_support/notifications"

require "cnfs_telemetry/version"
require "cnfs_telemetry/subscriber"
require "cnfs_telemetry/pry_console"
require "cnfs_telemetry/railtie" if defined?(Rails::Railtie)

# CnfsTelemetry bridges ActiveSupport::Notifications to OpenTelemetry.
#
# Every CNFS gem emits plain `ActiveSupport::Notifications` events via
# CnfsSupport::Instrumentable, under a `<component>.<class>.<verb>` naming
# convention where <component> is the underscored top-level module
# ("cnfs_okf.bundle.create"). Those gems depend on nothing telemetry-related.
# This gem is the ONE place that knows about OpenTelemetry: it subscribes to the
# `cnfs` family prefix and turns each event into a span on the OTel API tracer.
# It depends on `opentelemetry-api` only; until a host installs and configures
# the SDK, `OpenTelemetry.tracer_provider` is the API's no-op provider, so the
# whole bridge is free and harmless.
#
# Emit side (in any CNFS gem — no OTel dependency):
#
#   include CnfsSupport::Instrumentable
#   # ...
#   instrument(:create, bundle_id: id, path: path) do |payload|
#     # ... work whose duration becomes the span duration ...
#   end
#
# Bridge side (this gem, wired once by the host initializer):
#
#   CnfsTelemetry.install!   # subscribes to the "cnfs" event families
#
# The event name IS the span name. Its first dotted segment is the tracer's
# instrumentation-library name ("cnfs_okf.bundle.create" => tracer "cnfs_okf"),
# matching CnfsSupport::Logging's component tag so a gem's traces and logs align.
module CnfsTelemetry
  class << self
    # The event-name prefixes the bridge subscribes to. Every CNFS gem's events
    # begin with an underscored-module component ("cnfs_okf", "cnfs_iam", ...),
    # so the single "cnfs" prefix captures the whole family. Hosts may append
    # their own via `CnfsTelemetry.prefixes << "myapp"` before `install!`.
    def prefixes
      @prefixes ||= %w[cnfs]
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
  end
end
