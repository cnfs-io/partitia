require "spec_helper"

RSpec.describe CnfsSupport::Logging do
  # Two classes in distinct namespaces, defined once for the tag specs.
  before do
    stub_const("Okf::Button", Class.new { include CnfsSupport::Logging })
    stub_const("Chorus::Agent", Class.new { include CnfsSupport::Logging })
  end

  describe "component tagging" do
    it "tags each class with its first namespace segment, downcased" do
      expect(Okf::Button.logger.tag).to eq("okf")
      expect(Chorus::Agent.logger.tag).to eq("chorus")
    end

    it "gives instances the same logger as their class" do
      button = Okf::Button.new
      expect(button.logger).to be(Okf::Button.logger)
    end

    it "falls back to 'cnfs' for anonymous classes" do
      anon = Class.new { include CnfsSupport::Logging }
      expect(anon.logger.tag).to eq("cnfs")
    end
  end

  describe "per-tag levels" do
    let(:backend) { instance_spy(Logger) }

    before { described_class.backend = backend }

    it "emits an okf debug line but suppresses another tag's debug when only okf is verbose" do
      described_class.levels[:default] = :warn
      described_class.levels["okf"] = :debug

      Okf::Button.logger.debug("built")
      Chorus::Agent.logger.debug("spawned")

      expect(backend).to have_received(:debug).with("[okf] built")
      expect(backend).not_to have_received(:debug).with("[chorus] spawned")
    end

    it "emits at or above the tag's configured floor" do
      described_class.levels["okf"] = :warn

      Okf::Button.logger.info("noise")
      Okf::Button.logger.error("boom")

      expect(backend).not_to have_received(:info)
      expect(backend).to have_received(:error).with("[okf] boom")
    end
  end

  describe "block form" do
    let(:backend) { instance_spy(Logger) }

    before { described_class.backend = backend }

    it "does not evaluate the block when the level is disabled" do
      described_class.levels["okf"] = :info
      evaluated = false

      Okf::Button.logger.debug { evaluated = true }

      expect(evaluated).to be(false)
      expect(backend).not_to have_received(:debug)
    end

    it "evaluates and emits the block when the level is enabled" do
      described_class.levels["okf"] = :debug

      Okf::Button.logger.debug { "computed #{2 + 2}" }

      expect(backend).to have_received(:debug).with("[okf] computed 4")
    end
  end

  describe "backend resolution" do
    it "returns a stdlib Logger when Rails is undefined (degrade path)" do
      expect(defined?(Rails)).to be_nil
      expect(described_class.backend).to be_a(Logger)
    end

    it "logging still works with the stdlib fallback" do
      io = StringIO.new
      described_class.backend = Logger.new(io)
      described_class.levels[:default] = :info

      Okf::Button.logger.info("hello")

      expect(io.string).to include("[okf] hello")
    end

    it "defaults to Rails.logger when Rails is present" do
      rails_logger = instance_spy(Logger)
      rails = Class.new do
        define_singleton_method(:logger) { rails_logger }
      end
      stub_const("Rails", rails)

      described_class.levels[:default] = :info
      Okf::Button.logger.warn("via rails")

      expect(rails_logger).to have_received(:warn).with("[okf] via rails")
    end
  end

  describe "host override" do
    it "redirects output to a host-assigned backend" do
      io = StringIO.new
      described_class.backend = Logger.new(io)
      described_class.levels[:default] = :debug

      Chorus::Agent.logger.debug("routed")

      expect(io.string).to include("[chorus] routed")
    end
  end
end
