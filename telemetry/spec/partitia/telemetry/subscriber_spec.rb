require "spec_helper"

RSpec.describe Partitia::Telemetry::Subscriber do
  describe "without an SDK (API-only, zero-cost path)" do
    it "instrumenting a partitia event does not raise" do
      Partitia::Telemetry.install!
      expect do
        ActiveSupport::Notifications.instrument("partitia_okf.bundle.create", bundle_id: 1) { :ok }
      end.not_to raise_error
    end
  end

  describe "with a host-wired SDK (proves spans emit)" do
    before do
      OtelCapture.configure!
      OtelCapture.reset!
      Partitia::Telemetry.install!
    end

    it "translates a partitia event into a span named after the event" do
      ActiveSupport::Notifications.instrument("partitia_okf.bundle.create", bundle_id: 42, path: "/x") do
        :work
      end

      span = OtelCapture.captured_spans.find { |s| s.name == "partitia_okf.bundle.create" }
      expect(span).not_to be_nil
    end

    it "folds payload entries onto the span as namespaced attributes" do
      ActiveSupport::Notifications.instrument("partitia_okf.bundle.create", bundle_id: 42, path: "/x") { }

      span = OtelCapture.captured_spans.find { |s| s.name == "partitia_okf.bundle.create" }
      expect(span.attributes["partitia_okf.bundle.create.bundle_id"]).to eq(42)
      expect(span.attributes["partitia_okf.bundle.create.path"]).to eq("/x")
    end

    it "names the tracer after the event's first segment (the underscored module)" do
      ActiveSupport::Notifications.instrument("partitia_okf.bundle.create") { }

      span = OtelCapture.captured_spans.find { |s| s.name == "partitia_okf.bundle.create" }
      expect(span.instrumentation_scope.name).to eq("partitia_okf")
    end

    it "matches an underscored component across the segment boundary" do
      # Guards the prefix matcher: "partitia" must capture "partitia_okf.*" even though an
      # underscore (not a dot) follows the prefix. A naive /\Acnfs(\.|\z)/ misses this.
      ActiveSupport::Notifications.instrument("partitia_iam.session.open") { }

      expect(OtelCapture.captured_spans.map(&:name)).to include("partitia_iam.session.open")
    end

    it "nests inner partitia events under the outer span" do
      ActiveSupport::Notifications.instrument("partitia_okf.bundle.create") do
        ActiveSupport::Notifications.instrument("partitia_okf.concept.create") { }
      end

      outer = OtelCapture.captured_spans.find { |s| s.name == "partitia_okf.bundle.create" }
      inner = OtelCapture.captured_spans.find { |s| s.name == "partitia_okf.concept.create" }
      expect(inner.parent_span_id).to eq(outer.span_id)
    end

    it "marks the span errored when the block raises" do
      expect do
        ActiveSupport::Notifications.instrument("partitia_okf.bundle.create") { raise "boom" }
      end.to raise_error("boom")

      span = OtelCapture.captured_spans.find { |s| s.name == "partitia_okf.bundle.create" }
      expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    end

    it "does not subscribe to non-partitia prefixes" do
      ActiveSupport::Notifications.instrument("process_action.action_controller") { }
      expect(OtelCapture.captured_spans.map(&:name)).not_to include("process_action.action_controller")
    end
  end
end
