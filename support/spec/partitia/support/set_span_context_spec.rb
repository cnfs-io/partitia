require "spec_helper"

# .set_span_context enriches the currently-active span with attributes, reached
# only through a runtime `defined?(OpenTelemetry)` probe (same charter as the
# log↔trace bridge: zero load-time OTel coupling). Proven here against a real SDK
# span via OtelSpanCapture rather than pulling partitia-telemetry into this suite.
RSpec.describe Partitia::Support::Instrumentable, ".set_span_context" do
  before { OtelSpanCapture.reset! }

  def last_span_attributes
    OtelSpanCapture.captured_spans.last&.attributes || {}
  end

  # 1 — attributes land on the active recording span (the tenanted use case:
  # tenant.subdomain / tenant.handle stamped mid-request).
  it "stamps attributes onto the active recording span" do
    OtelSpanCapture.with_active_span do
      described_class.set_span_context(
        "tenant.subdomain" => "acme", "tenant.handle" => "h_123"
      )
    end

    expect(last_span_attributes).to include(
      "tenant.subdomain" => "acme", "tenant.handle" => "h_123"
    )
  end

  # 2 — nil values are dropped, not written (handle unknown until after the DB
  # lookup, so callers pass nil freely).
  it "drops nil values rather than writing them" do
    OtelSpanCapture.with_active_span do
      described_class.set_span_context(
        "tenant.subdomain" => "acme", "tenant.handle" => nil
      )
    end

    expect(last_span_attributes).to include("tenant.subdomain" => "acme")
    expect(last_span_attributes).not_to have_key("tenant.handle")
  end

  # 3 — OpenTelemetry undefined (OTel-absent host): no raise. Proves the guard is
  # a true probe, not a mere span check.
  it "does not raise when OpenTelemetry is not loaded" do
    hide_const("OpenTelemetry")

    expect { described_class.set_span_context(foo: "bar") }.not_to raise_error
  end

  # 4 — OpenTelemetry defined but no recording span on the context (untenanted
  # request / telemetry not installed): silent, no raise, no span created.
  it "is silent when no recording span is on the context" do
    expect { described_class.set_span_context(foo: "bar") }.not_to raise_error
    expect(OtelSpanCapture.captured_spans).to be_empty
  end
end
