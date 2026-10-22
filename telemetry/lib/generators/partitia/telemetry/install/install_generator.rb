require "rails/generators/base"

module Partitia
  module Telemetry
    module Generators
      # Wires a host app to export spans and report errors:
      #
      #   rails g partitia:telemetry:install
      #
      #   - Gemfile: opentelemetry-sdk, opentelemetry-exporter-otlp, sentry-rails
      #   - config/initializers/opentelemetry.rb  (SDK config from Partitia::Telemetry::Config)
      #   - config/initializers/sentry.rb         (Sentry/GlitchTip, on only when error_dsn is set)
      #
      # Idempotent (ARCHITECTURE §5): gems already in the Gemfile are not re-added,
      # and an existing initializer is the app's and is left alone, so a second run
      # changes nothing and asks nothing. No endpoint or DSN is written into the
      # app; both come from Partitia::Telemetry::Config at boot.
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Add the OpenTelemetry SDK and sentry-rails, and the initializers that configure them " \
             "from Partitia::Telemetry::Config."

        GEMS = %w[opentelemetry-sdk opentelemetry-exporter-otlp sentry-rails].freeze

        INITIALIZERS = {
          "opentelemetry.rb.tt" => "config/initializers/opentelemetry.rb",
          "sentry.rb.tt" => "config/initializers/sentry.rb"
        }.freeze

        # `bundle add` installs and locks in one step so the app boots after
        # install, but it fails on a gem already in the Gemfile, so add only the
        # missing ones. Runs before the initializers so a failed resolve never
        # leaves an initializer whose `require` can't load.
        def add_gems
          missing = GEMS.reject { |name| gem_in_gemfile?(name) }
          if missing.empty?
            say_status :identical, "Gemfile (#{GEMS.join(", ")})", :blue
            return
          end

          bundle_add(missing)
        end

        def create_initializers
          INITIALIZERS.each do |source, target|
            if File.exist?(File.join(destination_root, target))
              say_status :skip, "#{target} exists (app-owned)", :blue
            else
              template source, target
            end
          end
        end

        def print_post_install
          say ""
          say "partitia-telemetry installed.", :green
          say "  Gemfile: #{GEMS.join(", ")}"
          INITIALIZERS.each_value { |target| say "  #{target}" }
          say ""
          say "Settings: Partitia::Telemetry::Config (config/partitia_telemetry.yml, " \
              "credentials.partitia_telemetry, PARTITIA_TELEMETRY_*). OTEL_* still wins for the SDK."
          say ""
          say "Still to do:"
          say "  pcm up telemetry glitchtip", :yellow
          say "  Set PARTITIA_TELEMETRY_ERROR_DSN (or credentials partitia_telemetry.error_dsn) to the DSN"
          say "  from GlitchTip's project settings (Client Keys). Until then error reporting is off."
          say ""
          say "Traces export to #{Partitia::Telemetry::Config::DEFAULT_OTLP_ENDPOINT} (OTLP/HTTP) by default;"
          say "view them in Grafana (`pcm show telemetry` for its URL) under Explore -> Tempo."
          say ""
        end

        private

        def bundle_add(names)
          run "bundle add #{names.join(" ")}"
        end

        def gem_in_gemfile?(name)
          gemfile = File.join(destination_root, "Gemfile")
          File.exist?(gemfile) && File.read(gemfile).match?(/^\s*gem\s+["']#{Regexp.escape(name)}["']/)
        end
      end
    end
  end
end
