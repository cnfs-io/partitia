require "rails_helper"

RSpec.describe CnfsTenanted::Resolvers::HostHash do
  def resolve(host, map)
    described_class.new(map).call(FakeRequest.new(host: host))
  end

  it "maps a known host to its tenant" do
    expect(resolve("acme.com", "acme.com" => "acme")).to eq("acme")
  end

  it "returns nil (not an error) for an unmapped host" do
    expect(resolve("unknown.com", "acme.com" => "acme")).to be_nil
  end

  it "matches case-insensitively" do
    expect(resolve("ACME.com", "acme.com" => "acme")).to eq("acme")
  end

  it "ignores a leading www." do
    expect(resolve("www.acme.com", "acme.com" => "acme")).to eq("acme")
  end
end
