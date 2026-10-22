require "spec_helper"
require "stringio"

RSpec.describe "Partitia::Telemetry SDK-missing warning" do
  let(:io) { StringIO.new }
  let(:logger) { Logger.new(io) }

  before { Partitia::Telemetry.reset_sdk_warning! }
  after { Partitia::Telemetry.reset_sdk_warning! }

  context "when the SDK was never configured" do
    before { allow(Partitia::Telemetry).to receive(:sdk_configured?).and_return(false) }

    it "logs one line naming the generator, once per process" do
      expect(Partitia::Telemetry.warn_if_sdk_unconfigured!(logger)).to be(true)
      expect(Partitia::Telemetry.warn_if_sdk_unconfigured!(logger)).to be(false)

      lines = io.string.lines
      expect(lines.size).to eq(1)
      expect(lines.first).to include("spans go nowhere", "partitia:telemetry:install")
    end

    it "tags the line partitia_telemetry through partitia-support's logging by default" do
      allow(Partitia::Support::Logging).to receive(:backend).and_return(logger)
      Partitia::Telemetry.warn_if_sdk_unconfigured!
      expect(io.string).to include("[partitia_telemetry]")
    end
  end

  it "says nothing once the SDK is configured" do
    OtelCapture.configure!
    expect(Partitia::Telemetry.sdk_configured?).to be(true)
    expect(Partitia::Telemetry.warn_if_sdk_unconfigured!(logger)).to be(false)
    expect(io.string).to be_empty
  end
end
