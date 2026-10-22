require "rails_helper"

RSpec.describe CnfsTenanted::Resolvers::Subdomain do
  def resolve(host, **opts)
    described_class.new(**opts).call(FakeRequest.new(host: host))
  end

  it "returns the leftmost label as the tenant name" do
    expect(resolve("acme.example.com")).to eq("acme")
  end

  it "excludes www by default" do
    expect(resolve("www.example.com")).to be_nil
  end

  it "returns nil when there is no subdomain" do
    expect(resolve("example.com")).to be_nil
  end

  it "returns nil for an IPv4 host (never a tenant)" do
    expect(resolve("203.0.113.5")).to be_nil
  end

  it "returns nil for an IPv6 host" do
    expect(resolve("::1")).to be_nil
  end

  it "takes only the first label of a nested subdomain by default" do
    expect(resolve("acme.staging.example.com")).to eq("acme")
  end

  it "uses the full subdomain when first_label_only is false" do
    expect(resolve("acme.staging.example.com", first_label_only: false)).to eq("acme.staging")
  end

  it "honors a custom exclusion list" do
    expect(resolve("admin.example.com", excluded: %w[admin])).to be_nil
    expect(resolve("acme.example.com", excluded: %w[admin])).to eq("acme")
  end
end
