require "spec_helper"

RSpec.describe "partitia-telemetry.gemspec" do
  let(:spec) { Gem::Specification.load(File.expand_path("../../../partitia-telemetry.gemspec", __dir__)) }

  it "names the pcm services it needs" do
    expect(spec.metadata["partitia.services"]).to eq("telemetry glitchtip")
  end

  it "depends on partitia-support at runtime" do
    expect(spec.runtime_dependencies.map(&:name)).to include("partitia-support")
  end
end
