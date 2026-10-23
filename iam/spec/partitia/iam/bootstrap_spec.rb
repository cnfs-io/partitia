require "rails_helper"

RSpec.describe Partitia::Iam::Bootstrap do
  it "seeds the account and root in a database that has none, with a usable token" do
    result = described_class.call(name: "Shop", owner_email: "owner@shop.test")

    expect(result).not_to be_claimed
    expect(result.root).to be_root
    expect(result.root.email).to eq("owner@shop.test")
    expect(Partitia::Iam::Account.instance.name).to eq("Shop")
    expect(Partitia::Iam::HumanPrincipal.find_by_link_token(result.token)).to eq(result.root)
  end

  it "reissues an unclaimed root's token, and the old one stops working" do
    first = described_class.call(name: "Shop", owner_email: "owner@shop.test").token

    second = described_class.call(name: "Shop", owner_email: "owner@shop.test")

    expect(Partitia::Iam::HumanPrincipal.where(root: true).count).to eq(1)
    expect(Partitia::Iam::HumanPrincipal.find_by_link_token(first)).to be_nil
    expect(Partitia::Iam::HumanPrincipal.find_by_link_token(second.token)).to eq(second.root)
  end

  it "issues nothing once root has an identity link" do
    root = described_class.call(name: "Shop", owner_email: "owner@shop.test").root
    root.identity_links.create!(issuer: "https://idp", subject: "sub-1")

    result = described_class.call(name: "Shop", owner_email: "owner@shop.test")

    expect(result).to be_claimed
    expect(result.root).to eq(root)
  end

  it "is the token an :invite_only sign-in redeems, binding the identity to root" do
    token = described_class.call(name: "Shop", owner_email: "owner@shop.test").token
    assertion = Partitia::Iam::Assertion.new(issuer: "https://idp", subject: "akadmin-sub")

    result = Partitia::Iam::Resolution.resolve(assertion: assertion, policy: :invite_only, link_token: token)

    expect(result.principal).to be_root
    expect(described_class.call(name: "Shop", owner_email: "owner@shop.test")).to be_claimed
  end
end
