require "spec_helper"

RSpec.describe Partitia::Support::Instrumentable do
  # A stand-in for a namespaced CNFS model. stub_const gives it a real,
  # fully-qualified name so component_tag / demodulize behave as in production.
  before do
    stub_const("Partitia::Okf::Bundle", Class.new do
      include Partitia::Support::Instrumentable

      def do_create(&block)
        instrument(:create, bundle_id: 7, path: "/tmp/x", &block)
      end
    end)
  end

  describe ".event_name" do
    it "composes <component>.<class>.<verb> from a fully-qualified name" do
      expect(described_class.event_name("Partitia::Okf::Bundle", :create))
        .to eq("partitia_okf.bundle.create")
    end

    it "accepts a string verb identically" do
      expect(described_class.event_name("Partitia::Okf::Bundle", "create"))
        .to eq("partitia_okf.bundle.create")
    end

    it "reuses component_tag for the component half, so it matches the log tag" do
      component = described_class.event_name("Partitia::Okf::Bundle", :x).split(".").first
      expect(component).to eq(Partitia::Support.component_tag("Partitia::Okf::Bundle"))
    end
  end

  describe "#instrument (instance)" do
    it "emits an ActiveSupport::Notifications event named for the instance's class" do
      events = capture_events("partitia_okf.bundle.create") do
        Partitia::Okf::Bundle.new.do_create { :done }
      end

      expect(events.size).to eq(1)
    end

    it "passes the payload through and yields it for enrichment" do
      payload = nil
      ActiveSupport::Notifications.subscribe("partitia_okf.bundle.create") do |*, pl|
        payload = pl
      end

      Partitia::Okf::Bundle.new.do_create do |pl|
        pl[:concept_count] = 3
      end

      expect(payload[:bundle_id]).to eq(7)
      expect(payload[:path]).to eq("/tmp/x")
      expect(payload[:concept_count]).to eq(3)
    end

    it "returns the block's value" do
      result = Partitia::Okf::Bundle.new.do_create { :the_return }
      expect(result).to eq(:the_return)
    end
  end

  describe ".instrument (class-level)" do
    it "uses the class's own name as the subject" do
      events = capture_events("partitia_okf.bundle.build") do
        Partitia::Okf::Bundle.instrument(:build) { :ok }
      end

      expect(events.size).to eq(1)
    end
  end

  # Collect notifications matching an exact event name emitted during the block.
  def capture_events(name)
    seen = []
    sub = ActiveSupport::Notifications.subscribe(name) { |*args| seen << args }
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
