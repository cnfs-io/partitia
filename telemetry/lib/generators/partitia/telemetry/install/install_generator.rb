require "rails/generators/base"

module Partitia
  module Telemetry
    module Generators
      # Wires a host app to export spans and report errors:
      #
      #   rails g partitia:telemetry:install
      #
      #   - Gemfile: opentelemetry-sdk, opentelemetry-exporter-otlp, sentry-rails, and
      #     OTel's Rack, ActionPack and ActionView instrumentation (request spans)
      #   - config/initializers/opentelemetry.rb  (SDK config from Partitia::Telemetry::Config,
      #     request tracing behind its rack_tracing setting)
      #   - config/initializers/sentry.rb         (Sentry/GlitchTip, on only when error_dsn is set)
      #
      # Idempotent (ARCHITECTURE §5): gems already in the Gemfile are not re-added,
      # and an existing initializer is the app's and is left alone, so a second run
      # changes nothing and asks nothing. No endpoint or DSN is written into the
      # app; both come from Partitia::Telemetry::Config at boot.
      #
      # Upgrades: an opentelemetry.rb written before request tracing existed gets
      # the request_tracing block injected into its `OpenTelemetry::SDK.configure`
      # block (once: a file that mentions rack_tracing is left alone), and the
      # instrumentation gems are added like any missing gem.
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Add the OpenTelemetry SDK and sentry-rails, and the initializers that configure them " \
             "from Partitia::Telemetry::Config."

        GEMS = %w[
          opentelemetry-sdk opentelemetry-exporter-otlp sentry-rails
          opentelemetry-instrumentation-rack opentelemetry-instrumentation-action_pack
          opentelemetry-instrumentation-action_view
        ].freeze

        OTEL_INITIALIZER = "config/initializers/opentelemetry.rb".freeze

        # Where the request tracing block goes in an existing opentelemetry.rb.
        SDK_CONFIGURE = /^OpenTelemetry::SDK\.configure do \|(\w+)\|\n/

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
          added << "Gemfile: #{missing.join(", ")}"
        end

        def create_initializers
          INITIALIZERS.each do |source, target|
            if File.exist?(File.join(destination_root, target))
              say_status :skip, "#{target} exists (app-owned)", :blue
            else
              template source, target
              added << target
            end
          end
        end

        # An opentelemetry.rb from before rack_tracing: inject the block, or say
        # what to add when its configure block isn't the generated one.
        def add_request_tracing
          path = File.join(destination_root, OTEL_INITIALIZER)
          return if added.include?(OTEL_INITIALIZER) || !File.exist?(path)

          content = File.read(path)
          if content.include?("rack_tracing")
            say_status :identical, "#{OTEL_INITIALIZER} (rack_tracing)", :blue
          elsif (match = content.match(SDK_CONFIGURE))
            insert_into_file OTEL_INITIALIZER, request_tracing_snippet(match[1]) + "\n", after: SDK_CONFIGURE
            added << "#{OTEL_INITIALIZER}: request tracing (rack_tracing)"
          else
            say_status :manual, "#{OTEL_INITIALIZER}: no `OpenTelemetry::SDK.configure do |c|` block", :yellow
            say "Add inside your SDK configure block:"
            say request_tracing_snippet
          end
        end

        def print_post_install
          say ""
          say "partitia-telemetry installed.", :green
          if added.empty?
            say "  Nothing added: already installed."
          else
            say "  Added:"
            added.each { |line| say "    #{line}" }
          end
          say ""
          say "Settings: Partitia::Telemetry::Config (config/partitia_telemetry.yml, " \
              "credentials.partitia_telemetry, PARTITIA_TELEMETRY_*). OTEL_* still wins for the SDK."
          say ""
          say "Still to do:"
          say "  pt services   (pcm up telemetry; GlitchTip's project, its DSN stored as error_dsn)", :yellow
          say "  or set PARTITIA_TELEMETRY_ERROR_DSN (or credentials partitia_telemetry.error_dsn) yourself."
          say "  Until then error reporting is off."
          say ""
          say "Request spans (Rack, ActionPack, ActionView) are on; PARTITIA_TELEMETRY_RACK_TRACING=false"
          say "(or rack_tracing: false in config/partitia_telemetry.yml) turns them off."
          say ""
          say "Traces export to #{Partitia::Telemetry::Config::DEFAULT_OTLP_ENDPOINT} (OTLP/HTTP) by default;"
          say "view them in Grafana (`pcm show telemetry` for its URL) under Explore -> Tempo."
          say ""
        end

        private

        def added
          @added ||= []
        end

        # The `if Partitia::Telemetry::Config.rack_tracing ... end` block, for the
        # template and for upgrading an existing initializer. `var` is the name the
        # app's configure block gives its configurator.
        def request_tracing_snippet(var = "c")
          File.read(File.join(self.class.source_root, "request_tracing.rb")).gsub(/\bc\.use\b/, "#{var}.use")
        end

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
