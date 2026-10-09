module CnfsTelemetry
  # Installs the notification->span bridge during app boot. Doing it here (rather
  # than in the ejected initializer) means the subscriber is always attached in a
  # Rails host; the initializer's job is only to configure the OTel SDK, which is
  # what turns the otherwise no-op bridge into real exported spans.
  #
  # Runs after :load_config_initializers so a host initializer may customise
  # `CnfsTelemetry.prefixes` (or opt out) before the subscription is created.
  class Railtie < ::Rails::Railtie
    initializer "cnfs_telemetry.install", after: :load_config_initializers do
      CnfsTelemetry.install! unless CnfsTelemetry.installed?
    end

    # Contribute the `debug!` console command to cnfs_dev when present. Rails runs
    # `console` blocks only when a console session starts (rails console / bin/rails
    # c), never in web/job processes — and late enough that cnfs_dev is loaded. Same
    # pattern chorus/okf use for their console contributions.
    console do
      require "cnfs_telemetry/pry_console"
      CnfsTelemetry::PryConsole.install!
    end
  end
end
