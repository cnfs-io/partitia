require "rails_helper"

RSpec.describe Partitia::Iam::IdentityLink do
  let(:principal) { Partitia::Iam::HumanPrincipal.create!(name: "alice") }

  it "enforces uniqueness of (issuer, subject)" do
    principal.identity_links.create!(issuer: "https://idp.example", subject: "sub-1")
    dup = Partitia::Iam::IdentityLink.new(issuer: "https://idp.example", subject: "sub-1", principal: principal)
    expect(dup).not_to be_valid
    expect(dup.errors[:subject]).to be_present
  end

  it "allows one principal to hold links from multiple issuers" do
    principal.identity_links.create!(issuer: "https://google", subject: "g-1")
    principal.identity_links.create!(issuer: "https://apple", subject: "a-1")
    expect(principal.identity_links.count).to eq(2)
  end

  it "allows the same subject under different issuers" do
    principal.identity_links.create!(issuer: "https://google", subject: "shared")
    other = Partitia::Iam::IdentityLink.new(issuer: "https://apple", subject: "shared", principal: principal)
    expect(other).to be_valid
  end

  it "rejects a machine principal owner" do
    machine = Partitia::Iam::MachinePrincipal.create!(name: "worker")
    link = Partitia::Iam::IdentityLink.new(issuer: "https://idp", subject: "s", principal: machine)
    expect(link).not_to be_valid
    expect(link.errors[:principal]).to be_present
  end
end
