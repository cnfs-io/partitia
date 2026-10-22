module Partitia
  module Telemetry
    # Installs the notification->span bridge during app boot. Doing it here (rather
    # than in the ejected initializer) means the subscriber is always attached in a
    # Rails host; the initializer's job is only to configure the OTel SDK, which is
    # what turns the otherwise no-op bridge into real exported spans.
    #
    # Runs after :load_config_initializers so a host initializer may customise
    # `Partitia::Telemetry.prefixes` (or opt out) before the subscription is created.
    class Railtie < ::Rails::Railtie
      initializer "partitia_telemetry.install", after: :load_config_initializers do
        Partitia::Telemetry.install! unless Partitia::Telemetry.installed?
      end

      # Installed without its generator, the bridge would export nothing and say
      # nothing (ARCHITECTURE §7). After every initializer has run (so the app's
      # opentelemetry.rb had its chance), log one line if the SDK is still absent.
      config.after_initialize do
        Partitia::Telemetry.warn_if_sdk_unconfigured!
      end

      # Contribute the `debug!` console command to partitia-dev when present. Rails runs
      # `console` blocks only when a console session starts (rails console / bin/rails
      # c), never in web/job processes — and late enough that partitia-dev is loaded. Same
      # pattern chorus/okf use for their console contributions.
      console do
        require "partitia/telemetry/pry_console"
        Partitia::Telemetry::PryConsole.install!
      end
    end
  end
end
