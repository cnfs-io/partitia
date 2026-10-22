# Host-side SDK wiring, present in the test suite ONLY, to prove that spans
# actually emit when a host configures the SDK. The gem itself never depends on
# opentelemetry-sdk (see the gemspec) — this is exactly the "host opts in" path.
require "opentelemetry/sdk"

# A shared in-memory exporter + simple processor. Specs read `captured_spans` to
# assert on emitted spans. The provider is configured once; `reset!` clears
# captured spans between examples.
module OtelCapture
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

  def captured_spans
    exporter.finished_spans
  end

  def reset!
    exporter.reset
  end
end
