RSpec.describe Partitia::Dev do
  describe ".console" do
    it "raises without a block" do
      expect { described_class.console }.to raise_error(ArgumentError, /requires a block/)
    end

    it "yields a Builder and returns nil" do
      yielded = nil
      result = described_class.console { |c| yielded = c }

      expect(yielded).to be_a(Partitia::Dev::Builder)
      expect(result).to be_nil
    end

    it "appends across calls in registration order (one call per gem)" do
      described_class.console { |c| c.reset_task("first:task").namespace(DevFixtures::Chorus, "c") }
      described_class.console { |c| c.reset_task("second:task").namespace(DevFixtures::Curry, "c") }

      expect(described_class.reset_tasks).to eq(%w[first:task second:task])
      expect(described_class.namespaces.map { |n| n[:module] }).to eq([ DevFixtures::Chorus, DevFixtures::Curry ])
    end
  end

  describe "registries" do
    %i[namespaces models commands prompt_segments before_resets reset_tasks].each do |registry|
      it "#{registry} starts empty and is memoized" do
        expect(described_class.public_send(registry)).to eq([])
        expect(described_class.public_send(registry)).to be(described_class.public_send(registry))
      end
    end

    it "are populated without Rails or a console session" do
      expect(defined?(Rails::Railtie)).to be_nil
      expect { described_class.console { |c| c.command(:x) { 1 } } }.to change { described_class.commands.size }.by(1)
    end
  end
end
