require "rails/generators/base"

module Partitia
  module Telemetry
    module Generators
      # Wires a host app to emit spans:
      #
      #   rails g partitia:telemetry:install
      #
      #   - adds opentelemetry-sdk + opentelemetry-exporter-otlp to the Gemfile
      #   - config/initializers/opentelemetry.rb   (app-owned SDK config + install!)
      #
      # The initializer is shipped as a template (single source of truth); each app
      # gets its own editable copy. Nothing here is loaded from the packaged gem at
      # runtime — it is all generator source. The telemetry stack itself is external
      # (see chorus/services/telemetry), not ejected by this gem.
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Add the OpenTelemetry SDK gems and install the app-owned SDK initializer."

        # Exposed to the initializer template.
        def app_name
          app_cls = Rails.application.class
          (app_cls.respond_to?(:module_parent_name) ? app_cls.module_parent_name : app_cls.parent_name)
            .underscore.dasherize
        rescue StandardError
          "rails-app"
        end

        def add_sdk_gems
          # The ejected initializer requires the SDK + OTLP exporter, which the host
          # owns. `bundle add` installs them and updates the lockfile in one step so
          # the app boots after install — and it is idempotent (skips gems already
          # present), unlike the raw `gem` action which appends a duplicate line on
          # re-run. Runs before create_initializer so a failed resolve never leaves
          # an initializer whose `require` can't load.
          run "bundle add opentelemetry-sdk opentelemetry-exporter-otlp"
        end

        def create_initializer
          template "opentelemetry.rb.tt", "config/initializers/opentelemetry.rb"
        end

        def print_post_install
          say ""
          say "partitia-telemetry installed.", :green
          say "  - opentelemetry-sdk + opentelemetry-exporter-otlp added to the Gemfile"
          say "  - config/initializers/opentelemetry.rb  (app-owned SDK config; edit freely)"
          say ""
          say "Traces export to a telemetry stack over OTLP (localhost:4318 by default)."
          say "Bring one up — e.g. the shared stack at chorus/services/telemetry:"
          say "  podman compose up -d", :yellow
          say "Then view traces in Grafana at http://localhost:8080 (Explore -> Tempo)."
          say ""
        end
      end
    end
  end
end
