require "spec_helper"

RSpec.describe Partitia::Support::Logging do
  # Two classes in distinct namespaces, defined once for the tag specs.
  before do
    stub_const("Okf::Button", Class.new { include Partitia::Support::Logging })
    stub_const("Chorus::Agent", Class.new { include Partitia::Support::Logging })
  end

  describe "component tagging" do
    it "tags each class with its component (partitia-prefixed, from the first segment)" do
      expect(Okf::Button.logger.tag).to eq("partitia_okf")
      expect(Chorus::Agent.logger.tag).to eq("partitia_chorus")
    end

    it "gives instances the same logger as their class" do
      button = Okf::Button.new
      expect(button.logger).to be(Okf::Button.logger)
    end

    it "falls back to the 'partitia' tag for an anonymous (nameless) class" do
      anon = Class.new { include Partitia::Support::Logging }
      expect(anon.logger.tag).to eq("partitia")
    end
  end

  describe "per-tag levels" do
    let(:backend) { instance_spy(Logger) }

    before { described_class.backend = backend }

    it "emits one tag's debug while suppressing another's when only the first is verbose" do
      described_class.levels[:default] = :warn
      described_class.levels["partitia_okf"] = :debug

      Okf::Button.logger.debug("built")
      Chorus::Agent.logger.debug("spawned")

      expect(backend).to have_received(:debug).with("[partitia_okf] built")
      expect(backend).not_to have_received(:debug).with("[partitia_chorus] spawned")
    end

    it "emits at or above the tag's configured floor" do
      described_class.levels["partitia_okf"] = :warn

      Okf::Button.logger.info("noise")
      Okf::Button.logger.error("boom")

      expect(backend).not_to have_received(:info)
      expect(backend).to have_received(:error).with("[partitia_okf] boom")
    end
  end

  describe "block form" do
    let(:backend) { instance_spy(Logger) }

    before { described_class.backend = backend }

    it "does not evaluate the block when the level is disabled" do
      described_class.levels["partitia_okf"] = :info
      evaluated = false

      Okf::Button.logger.debug { evaluated = true }

      expect(evaluated).to be(false)
      expect(backend).not_to have_received(:debug)
    end

    it "evaluates and emits the block when the level is enabled" do
      described_class.levels["partitia_okf"] = :debug

      Okf::Button.logger.debug { "computed #{2 + 2}" }

      expect(backend).to have_received(:debug).with("[partitia_okf] computed 4")
    end
  end

  describe "backend resolution" do
    it "returns a stdlib Logger when Rails is undefined (degrade path)" do
      expect(defined?(Rails)).to be_nil
      expect(described_class.backend).to be_a(Logger)
    end

    it "defaults to Rails.logger when Rails is present" do
      rails_logger = instance_spy(Logger)
      rails = Class.new do
        define_singleton_method(:logger) { rails_logger }
      end
      stub_const("Rails", rails)

      described_class.levels[:default] = :info
      Okf::Button.logger.warn("via rails")

      expect(rails_logger).to have_received(:warn).with("[partitia_okf] via rails")
    end
  end

  describe "host override" do
    it "redirects output to a host-assigned backend, tagged and formatted" do
      io = StringIO.new
      described_class.backend = Logger.new(io)
      described_class.levels[:default] = :info

      Okf::Button.logger.info("hello")

      expect(io.string).to include("[partitia_okf] hello")
    end
  end
end
