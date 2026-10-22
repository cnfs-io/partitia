require "rails_helper"

RSpec.describe Iam::RootRecovery do
  it "invalidates the root's links and old token, issuing a fresh usable one" do
    root = Iam::HumanPrincipal.create!(name: "root", email: "root@acme.test", root: true)
    root.identity_links.create!(issuer: "https://idp", subject: "sub-1")
    old_token = root.issue_link_token!

    new_token = described_class.reset!

    expect(root.reload.identity_links).to be_empty
    expect(Iam::HumanPrincipal.find_by_link_token(old_token)).to be_nil
    expect(Iam::HumanPrincipal.find_by_link_token(new_token)).to eq(root)
  end

  it "raises when there is no root in the current database" do
    expect { described_class.reset! }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
