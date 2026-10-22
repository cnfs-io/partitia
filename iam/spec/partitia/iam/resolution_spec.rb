require "rails_helper"

RSpec.describe Partitia::Iam::Resolution do
  def assertion(**overrides)
    { issuer: "https://idp.example", subject: "sub-1", email: "uma@x.test", name: "Uma" }.merge(overrides)
  end

  describe ":jit policy" do
    it "creates a principal + link for an unknown identity, carrying email/name" do
      result = described_class.resolve(assertion: assertion, policy: :jit)

      expect(result).to be_success
      expect(result.principal.email).to eq("uma@x.test")
      expect(result.principal.name).to eq("Uma")
      expect(result.principal.identity_links.pluck(:issuer, :subject)).to eq([ [ "https://idp.example", "sub-1" ] ])
    end

    it "is idempotent — a repeat login reuses the same principal" do
      first = described_class.resolve(assertion: assertion, policy: :jit)
      second = described_class.resolve(assertion: assertion, policy: :jit)

      expect(second.principal).to eq(first.principal)
      expect(Partitia::Iam::HumanPrincipal.count).to eq(1)
    end

    it "returns the linked principal for a known identity" do
      created = described_class.resolve(assertion: assertion, policy: :jit).principal
      again = described_class.resolve(assertion: assertion, policy: :jit)
      expect(again.principal).to eq(created)
    end
  end

  describe ":invite_only policy" do
    it "returns the linked principal for a known identity" do
      principal = Partitia::Iam::HumanPrincipal.create!(name: "op")
      principal.identity_links.create!(issuer: assertion[:issuer], subject: assertion[:subject])

      result = described_class.resolve(assertion: assertion, policy: :invite_only)
      expect(result.principal).to eq(principal)
    end

    it "fails closed for an unknown identity with no token" do
      result = described_class.resolve(assertion: assertion, policy: :invite_only)

      expect(result).not_to be_success
      expect(result.failure_reason).to eq(Partitia::Iam::Resolution::UNKNOWN_IDENTITY)
      expect(Partitia::Iam::HumanPrincipal.count).to eq(0)
    end

    it "binds and consumes a valid link token, then rejects its reuse" do
      principal = Partitia::Iam::HumanPrincipal.create!(name: "invitee")
      token = principal.issue_link_token!

      result = described_class.resolve(assertion: assertion, policy: :invite_only, link_token: token)
      expect(result.principal).to eq(principal)
      expect(principal.reload.link_token_digest).to be_nil

      # A different assertion replaying the same (now consumed) token fails.
      replay = described_class.resolve(
        assertion: assertion(subject: "sub-2"), policy: :invite_only, link_token: token
      )
      expect(replay.failure_reason).to eq(Partitia::Iam::Resolution::INVALID_LINK_TOKEN)
    end

    it "rejects a wrong or expired token" do
      Partitia::Iam::HumanPrincipal.create!(name: "invitee").issue_link_token!

      wrong = described_class.resolve(assertion: assertion, policy: :invite_only, link_token: "iam_secret_bogus")
      expect(wrong.failure_reason).to eq(Partitia::Iam::Resolution::INVALID_LINK_TOKEN)
    end

    it "bootstraps a seeded root end-to-end (invite_only + token)" do
      root = Partitia::Iam::HumanPrincipal.create!(name: "root", email: "root@acme.test", root: true)
      token = root.issue_link_token!

      result = described_class.resolve(
        assertion: assertion(email: "root@acme.test"), policy: :invite_only, link_token: token
      )

      expect(result.principal).to eq(root)
      expect(result.principal.root?).to be(true)
    end
  end

  describe "unknown / absent policy" do
    it "fails closed" do
      expect(described_class.resolve(assertion: assertion, policy: :bogus).failure_reason)
        .to eq(Partitia::Iam::Resolution::INVALID_POLICY)
      expect(described_class.resolve(assertion: assertion, policy: nil).failure_reason)
        .to eq(Partitia::Iam::Resolution::INVALID_POLICY)
    end
  end
end
