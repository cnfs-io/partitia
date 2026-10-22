require "rails_helper"

RSpec.describe Partitia::Cognito::Providers::Registry do
  it "registers and fetches a provider by name" do
    provider = Object.new
    described_class.register(:authentik, provider)
    expect(described_class.fetch(:authentik)).to be(provider)
    expect(described_class.registered?(:authentik)).to be(true)
  end

  it "raises for an unknown provider name" do
    expect { described_class.fetch(:nope) }.to raise_error(Partitia::Cognito::ConfigurationError)
  end
end
