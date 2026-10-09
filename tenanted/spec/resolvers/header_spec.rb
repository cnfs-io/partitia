require "rails_helper"

RSpec.describe CnfsTenanted::Resolvers::Header do
  def resolve(headers, **opts)
    described_class.new(**opts).call(FakeRequest.new(host: "example.com", headers: headers))
  end

  it "reads the default X-Tenant-Id header" do
    expect(resolve({ "HTTP_X_TENANT_ID" => "acme" })).to eq("acme")
  end

  it "reads a custom header" do
    expect(resolve({ "HTTP_X_ACME_ORG" => "acme" }, header: "X-Acme-Org")).to eq("acme")
  end

  it "returns nil when the header is absent" do
    expect(resolve({})).to be_nil
  end

  it "defaults to untrusted" do
    expect(described_class.new.trusted).to be(false)
  end
end
