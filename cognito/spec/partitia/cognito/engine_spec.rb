require "rails_helper"

RSpec.describe Partitia::Cognito::Engine do
  it "registers itself with partitia-support (ARCHITECTURE §3)" do
    expect(Partitia::Support.plugins).to include(described_class)
    expect(Partitia::Support.each_plugin.to_a).to include(described_class)
  end

  it "names the pcm service it needs (ARCHITECTURE §9)" do
    spec = Gem::Specification.load(File.expand_path("../../../partitia-cognito.gemspec", __dir__))
    expect(spec.metadata["partitia.services"]).to eq("authentik")
  end
end
