  # Request spans: the standard OTel Rack instrumentation opens one span per
  # request (named `GET /users/:id` by ActionPack, with the controller and
  # route as attributes) and ActionView adds template render spans under it;
  # the partitia_* spans nest inside. ActiveRecord is not traced.
  # Partitia::Telemetry::Config.rack_tracing, default true;
  # PARTITIA_TELEMETRY_RACK_TRACING=false turns it off.
  if Partitia::Telemetry::Config.rack_tracing
    require "opentelemetry/instrumentation/rack"
    require "opentelemetry/instrumentation/action_pack"
    require "opentelemetry/instrumentation/active_support" # ActionView's railtie needs it loaded
    require "opentelemetry/instrumentation/action_view"
    c.use "OpenTelemetry::Instrumentation::Rack"
    c.use "OpenTelemetry::Instrumentation::ActionPack"
    c.use "OpenTelemetry::Instrumentation::ActionView"
  end
