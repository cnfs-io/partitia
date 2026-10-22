require "spec_helper"

# Log↔trace bridge (plan 03). Proves that, opted in, an emitted log line is
# mirrored as a span event on the currently-active recording span — reached only
# through a runtime `defined?(OpenTelemetry)` probe, so `partitia-support` keeps zero
# load-time OTel coupling. This is the UNIT harness: it stands up a real SDK span
# via OtelSpanCapture rather than pulling partitia-telemetry into this suite.
RSpec.describe Partitia::Support::Logging, "log↔trace bridge" do
  let(:backend) { instance_spy(Logger) }

  before do
    stub_const("Partitia::Iam::Token", Class.new { include Partitia::Support::Logging })
    described_class.backend = backend
    described_class.levels[:default] = :debug
  end

  def event_named(events, name)
    events.find { |e| e.name == name }
  end

  # 1 — flag OFF (default): no span events even with a recording span active.
  it "adds no span event when bridging is off, even inside a recording span" do
    OtelSpanCapture.with_active_span do
      Partitia::Iam::Token.logger.info("minted")
    end

    expect(OtelSpanCapture.last_span_events).to be_empty
    expect(backend).to have_received(:info).with("[partitia_iam] minted")
  end

  # 2 — flag ON, recording span attached: line becomes a span event carrying the
  # log.severity + log.tag attributes.
  it "mirrors a passing line as a span event with severity and tag attributes" do
    described_class.bridge_to_spans = true

    OtelSpanCapture.with_active_span do
      Partitia::Iam::Token.logger.info("minted")
    end

    event = event_named(OtelSpanCapture.last_span_events, "minted")
    expect(event).not_to be_nil
    expect(event.attributes).to include(
      "log.severity" => "info",
      "log.tag" => "partitia_iam"
    )
    # Still mirrored to the backend — bridging does not divert.
    expect(backend).to have_received(:info).with("[partitia_iam] minted")
  end

  # 3 — flag ON, OpenTelemetry undefined (OTel-absent host): logging still works,
  # no raise. Proves the `defined?` guard is a true probe, not a mere span check.
  it "does not raise when OpenTelemetry is not loaded" do
    described_class.bridge_to_spans = true
    hide_const("OpenTelemetry")

    expect { Partitia::Iam::Token.logger.info("minted") }.not_to raise_error
    expect(backend).to have_received(:info).with("[partitia_iam] minted")
  end

  # 4 — flag ON, OpenTelemetry defined but no active recording span (common case:
  # logging outside any instrument block): no event, no raise.
  it "is silent when no recording span is on the context" do
    described_class.bridge_to_spans = true

    expect { Partitia::Iam::Token.logger.info("minted") }.not_to raise_error
    expect(OtelSpanCapture.captured_spans).to be_empty
    expect(backend).to have_received(:info).with("[partitia_iam] minted")
  end

  # 5 — flag ON, line rides a span opened by a DIFFERENT component: log.tag still
  # reads the line's own component, preserving its identity.
  it "keeps the line's own tag when riding a span from another component" do
    described_class.bridge_to_spans = true

    OtelSpanCapture.with_active_span("partitia_okf") do
      Partitia::Iam::Token.logger.warn("suspicious")
    end

    event = event_named(OtelSpanCapture.last_span_events, "suspicious")
    expect(event.attributes).to include("log.tag" => "partitia_iam")
  end

  # 6 — level filter gates the bridge too: a line below threshold is neither
  # logged nor bridged, and the block is never evaluated.
  it "does not bridge a line below the tag's level threshold" do
    described_class.bridge_to_spans = true
    described_class.levels["partitia_iam"] = :warn
    evaluated = false

    OtelSpanCapture.with_active_span do
      Partitia::Iam::Token.logger.debug { evaluated = true; "noise" }
    end

    expect(evaluated).to be(false)
    expect(OtelSpanCapture.last_span_events).to be_empty
    expect(backend).not_to have_received(:debug)
  end
end
