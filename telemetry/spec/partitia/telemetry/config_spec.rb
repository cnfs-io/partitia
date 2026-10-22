require "spec_helper"

RSpec.describe Partitia::Telemetry::Config do
  # Clear every OTEL_* var the config consults, so the host shell can't leak in.
  def clean(extra = {}, &block)
    otel = (%w[OTEL_SERVICE_NAME] + described_class::OTEL_EXPORTER_ENV).to_h { |k| [ k, nil ] }
    with_env(otel.merge(extra), &block)
  end

  it "is a Partitia::Support::Config named partitia_telemetry" do
    expect(described_class.superclass).to eq(Partitia::Support::Config)
    expect(described_class.config_name).to eq("partitia_telemetry")
  end

  describe "defaults" do
    it "points at pcm's telemetry collector, reports no errors, subscribes to partitia" do
      clean do
        expect(described_class.otlp_endpoint).to eq("http://localhost:4318")
        expect(described_class.error_dsn).to be_nil
        expect(described_class.error_reporting?).to be(false)
        expect(described_class.prefix_list).to eq(%w[partitia])
        expect(described_class.service_name).to be_nil
      end
    end

    it "has no service name outside a Rails app" do
      clean { expect(described_class.resolved_service_name).to be_nil }
    end

    it "derives the service name from the Rails app's module, underscored" do
      app = Class.new
      app.define_singleton_method(:module_parent_name) { "MyShop" }
      rails = Module.new
      rails.define_singleton_method(:application) { app.new }
      stub_const("Rails", rails)

      clean { expect(described_class.resolved_service_name).to eq("my_shop") }
    end
  end

  describe "PARTITIA_TELEMETRY_* overrides" do
    it "reads each setting from ENV" do
      clean(
        "PARTITIA_TELEMETRY_SERVICE_NAME" => "shop",
        "PARTITIA_TELEMETRY_OTLP_ENDPOINT" => "http://collector:4318/",
        "PARTITIA_TELEMETRY_ERROR_DSN" => "http://key@glitchtip:8000/1",
        "PARTITIA_TELEMETRY_PREFIXES" => "partitia,myapp"
      ) do
        expect(described_class.resolved_service_name).to eq("shop")
        expect(described_class.sdk_traces_endpoint).to eq("http://collector:4318/v1/traces")
        expect(described_class.error_reporting?).to be(true)
        expect(described_class.prefix_list).to eq(%w[partitia myapp])
        expect(Partitia::Telemetry.prefixes).to eq(%w[partitia myapp])
      end
    end
  end

  describe "OTEL_* precedence for the SDK" do
    it "hands the SDK the config's values when no OTEL_* var is set" do
      clean("PARTITIA_TELEMETRY_SERVICE_NAME" => "shop") do
        expect(described_class.sdk_service_name).to eq("shop")
        expect(described_class.sdk_traces_endpoint).to eq("http://localhost:4318/v1/traces")
      end
    end

    it "defers the service name to OTEL_SERVICE_NAME" do
      clean("PARTITIA_TELEMETRY_SERVICE_NAME" => "shop", "OTEL_SERVICE_NAME" => "other") do
        expect(described_class.sdk_service_name).to be_nil
      end
    end

    %w[OTEL_EXPORTER_OTLP_ENDPOINT OTEL_EXPORTER_OTLP_TRACES_ENDPOINT OTEL_TRACES_EXPORTER].each do |var|
      it "defers the exporter to #{var}" do
        clean(var => "x") { expect(described_class.sdk_traces_endpoint).to be_nil }
      end
    end
  end
end
