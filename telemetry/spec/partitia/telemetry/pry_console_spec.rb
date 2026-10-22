require "spec_helper"

RSpec.describe Partitia::Telemetry::PryConsole do
  # notif! attaches/detaches a real subscriber on the process-global bus; make
  # sure each example starts and ends in the OFF state.
  def reset_notif!
    described_class.notif! if described_class.notif.end_with?("ON")
  end

  before { reset_notif! }
  after  { reset_notif! }

  it "starts OFF" do
    expect(described_class.notif).to eq("telemetry notif OFF")
  end

  it "notif! toggles ON then OFF, echoing the resulting state each time" do
    expect(described_class.notif!).to eq("telemetry notif ON")
    expect(described_class.notif).to eq("telemetry notif ON")

    expect(described_class.notif!).to eq("telemetry notif OFF")
    expect(described_class.notif).to eq("telemetry notif OFF")
  end

  it "logs partitia events while ON" do
    logged = []
    allow(described_class).to receive(:partitia_telemetry_log) { |msg| logged << msg }

    described_class.notif!
    ActiveSupport::Notifications.instrument("partitia_okf.bundle.create", bundle_id: 9) { :ok }

    expect(logged.join).to include("partitia_okf.bundle.create")
    expect(logged.join).to include("bundle_id")
  end

  it "does not log after being toggled OFF" do
    logged = []
    allow(described_class).to receive(:partitia_telemetry_log) { |msg| logged << msg }

    described_class.notif!   # ON
    described_class.notif!   # OFF
    ActiveSupport::Notifications.instrument("partitia_okf.bundle.create") { :ok }

    expect(logged).to be_empty
  end

  describe ".install!" do
    it "is a no-op when partitia-dev is absent" do
      hide_const("Partitia::Dev") if defined?(Partitia::Dev)
      expect { described_class.install! }.not_to raise_error
    end

    it "registers a notif! command with partitia-dev's console when present" do
      fake_builder = double("builder")
      fake_partitia_dev = Module.new do
        def self.console
          yield(@builder)
        end
      end
      fake_partitia_dev.instance_variable_set(:@builder, fake_builder)
      stub_const("Partitia::Dev", fake_partitia_dev)

      expect(fake_builder).to receive(:command).with(:notif!)
      described_class.install!
    end
  end
end
