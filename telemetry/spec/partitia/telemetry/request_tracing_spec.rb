require "spec_helper"
require "rack"
require "rack/mock"

# rack_tracing: the block the installer writes into the app's
# `OpenTelemetry::SDK.configure` (templates/request_tracing.rb), and the request
# span it produces parenting the partitia_* spans. No collector: the suite's
# in-memory exporter (spec/support/otel_sdk.rb).
RSpec.describe "request tracing (rack_tracing)" do
  describe "the generated SDK configure block" do
    let(:snippet_path) do
      File.expand_path("../../../lib/generators/partitia/telemetry/install/templates/request_tracing.rb", __dir__)
    end

    def instrumentation_used(env_value)
      c = double("OpenTelemetry::SDK::Configurator")
      used = []
      allow(c).to receive(:use) { |name| used << name }
      with_env("PARTITIA_TELEMETRY_RACK_TRACING" => env_value) do
        eval(File.read(snippet_path), binding, snippet_path) # rubocop:disable Security/Eval
      end
      used
    end

    it "uses Rack, ActionPack and ActionView by default" do
      expect(instrumentation_used(nil)).to eq(%w[
        OpenTelemetry::Instrumentation::Rack
        OpenTelemetry::Instrumentation::ActionPack
        OpenTelemetry::Instrumentation::ActionView
      ])
    end

    # ActionView's railtie references it in after_initialize; a real app failed to boot without it
    it "loads OTel's ActiveSupport instrumentation for ActionView's railtie" do
      instrumentation_used(nil)
      expect(defined?(OpenTelemetry::Instrumentation::ActiveSupport::Instrumentation)).to be_truthy
    end

    it "uses nothing with PARTITIA_TELEMETRY_RACK_TRACING=false" do
      expect(instrumentation_used("false")).to be_empty
    end

    it "leaves ActiveRecord untraced" do
      expect(instrumentation_used(nil).grep(/ActiveRecord/)).to be_empty
    end
  end

  describe "spans" do
    before do
      OtelCapture.configure!
      OtelCapture.reset!
      Partitia::Telemetry.install!
    end

    let(:engine_app) do
      lambda do |_env|
        ActiveSupport::Notifications.instrument("partitia_cognito.sessions_controller.login_start", provider: "x") { }
        [ 302, { "location" => "/idp" }, [] ]
      end
    end

    def get(app, path)
      Rack::MockRequest.new(app).get(path)
      OtelCapture.captured_spans
    end

    it "with the Rack instrumentation, opens a request span that parents the partitia_* span" do
      require "opentelemetry/instrumentation/rack"
      rack = OpenTelemetry::Instrumentation::Rack::Instrumentation.instance
      rack.install({})
      middleware, *args = rack.middleware_args
      app = Rack::Builder.new.tap { |b| b.use(middleware, *args) }.tap { |b| b.run(engine_app) }.to_app

      spans = get(app, "/auth/login")

      request = spans.find { |s| s.kind == :server }
      engine = spans.find { |s| s.name == "partitia_cognito.sessions_controller.login_start" }
      expect(request.name).to eq("GET")
      expect(engine.trace_id).to eq(request.trace_id)
      expect(engine.parent_span_id).to eq(request.span_id)
    end

    it "without it, has no request span and the partitia_* span is a root" do
      spans = get(engine_app, "/auth/login")

      expect(spans.map(&:name)).to eq(%w[partitia_cognito.sessions_controller.login_start])
      expect(spans.first.parent_span_id).to eq(OpenTelemetry::Trace::INVALID_SPAN_ID)
    end
  end
end
