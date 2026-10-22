# SDK-backed span capture for the log↔trace bridge unit harness. Present in the
# test suite ONLY (opentelemetry-sdk is a dev/test dependency; the gem's runtime
# charter stays OTel-free). This stands up a real recording span and puts it on
# the OTel context — mirroring what partitia-telemetry's subscriber does out-of-band
# around an instrument(...) block — so the bridge can be proven without pulling
# partitia-telemetry into this suite.
require "opentelemetry/sdk"

module OtelSpanCapture
  module_function

  def exporter
    @exporter ||= OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
  end

  def configure!
    return if @configured

    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
      )
    end
    @configured = true
  end

  # Open a recording span from `tracer_name`, attach it to the OTel context for
  # the duration of the block, then end it. Yields the live span. This is the
  # exact shape of partitia/telemetry/subscriber.rb's Context.attach, so a log line
  # fired inside the block sees this span via Trace.current_span.
  def with_active_span(tracer_name = "partitia_support_spec")
    configure!
    span = OpenTelemetry.tracer_provider.tracer(tracer_name).start_span("test")
    token = OpenTelemetry::Context.attach(
      OpenTelemetry::Trace.context_with_span(span)
    )
    yield span
  ensure
    OpenTelemetry::Context.detach(token) if token
    span&.finish
  end

  # Events recorded on the most recently finished span.
  def last_span_events
    exporter.finished_spans.last&.events || []
  end

  def captured_spans
    exporter.finished_spans
  end

  def reset!
    exporter.reset
  end
end
