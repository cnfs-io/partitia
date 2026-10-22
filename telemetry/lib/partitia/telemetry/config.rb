require "partitia/support/config"

module Partitia
  module Telemetry
    # The app's observability settings (ARCHITECTURE §4, §7, Q2). Resolves, in
    # ascending priority:
    #
    #   config/partitia_telemetry.yml → credentials.partitia_telemetry → PARTITIA_TELEMETRY_*
    #
    # Settings:
    #
    #   service_name   OTel `service.name`. nil (default) derives it from the Rails
    #                  app's module name, underscored (`MyShop::Application` →
    #                  "my_shop"); see #resolved_service_name.
    #   otlp_endpoint  Base URL of the OTLP/HTTP collector (no `/v1/traces`).
    #                  Defaults to pcm's `stack/telemetry` collector.
    #   error_dsn      GlitchTip/Sentry DSN. nil (default) = error reporting off.
    #                  A secret: set it in credentials or PARTITIA_TELEMETRY_ERROR_DSN,
    #                  never as a literal in the app.
    #   prefixes       Event-name prefixes the span bridge subscribes to
    #                  (`PARTITIA_TELEMETRY_PREFIXES=partitia,myapp`).
    #
    # The standard OTEL_* variables still win for the OTel SDK (OTel's own
    # convention): when one is set, the sdk_* readers below return nil and the
    # generated initializer leaves that setting to the SDK.
    class Config < Partitia::Support::Config
      config_name :partitia_telemetry

      DEFAULT_OTLP_ENDPOINT = "http://localhost:4318".freeze
      DEFAULT_PREFIXES = %w[partitia].freeze

      # OTel variables that, when set, mean the SDK picks the exporter/endpoint
      # itself (OTEL_TRACES_EXPORTER=none|console included).
      OTEL_EXPORTER_ENV = %w[
        OTEL_EXPORTER_OTLP_ENDPOINT
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
        OTEL_TRACES_EXPORTER
      ].freeze

      attr_config :service_name, :error_dsn,
                  otlp_endpoint: DEFAULT_OTLP_ENDPOINT,
                  prefixes: DEFAULT_PREFIXES

      # service_name, else the Rails app's module name underscored, else nil.
      def resolved_service_name
        name = service_name.to_s.strip
        return name unless name.empty?

        rails_app_name
      end

      # Prefixes as an array of strings (ENV gives a comma list or a single string).
      def prefix_list
        Array(prefixes).flat_map { |p| p.to_s.split(",") }.map(&:strip).reject(&:empty?)
      end

      def error_reporting?
        !error_dsn.to_s.strip.empty?
      end

      # The service.name to hand the SDK, or nil when OTEL_SERVICE_NAME is set
      # (the SDK's resource detection then supplies it).
      def sdk_service_name
        return nil if otel_env?("OTEL_SERVICE_NAME")

        resolved_service_name
      end

      # The full OTLP/HTTP traces URL to hand the exporter, or nil when any OTEL_*
      # exporter variable is set (the SDK then builds the exporter from ENV).
      def sdk_traces_endpoint
        return nil if OTEL_EXPORTER_ENV.any? { |var| otel_env?(var) }

        "#{otlp_endpoint.to_s.chomp("/")}/v1/traces"
      end

      private

      def otel_env?(var)
        !ENV[var].to_s.strip.empty?
      end

      def rails_app_name
        return nil unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application

        ::Rails.application.class.module_parent_name.underscore
      rescue StandardError
        nil
      end
    end
  end
end
