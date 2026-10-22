require "rails_helper"

RSpec.describe Iam::Urn do
  describe ".build" do
    it "produces the AWS-shaped grammar with an empty region for IAM" do
      urn = described_class.build(account: "a7f3k2xy", resource_type: "user", resource_id: "alice")
      expect(urn).to eq("urn:cnfs:iam::a7f3k2xy:user/alice")
    end

    it "honours a host-configured partition" do
      urn = described_class.build(account: "a7f3k2xy", resource_type: "user", resource_id: "alice", partition: "acme")
      expect(urn).to start_with("urn:acme:iam:")
    end
  end

  describe ".parse round-trip" do
    it "parses a built URN back into its parts" do
      urn = described_class.build(account: "a7f3k2xy", resource_type: "access_key", resource_id: "iam_v1_x")
      parsed = described_class.parse(urn)

      expect(parsed).to be_valid
      expect(parsed.partition).to eq("cnfs")
      expect(parsed.service).to eq("iam")
      expect(parsed.region).to eq("")
      expect(parsed.account).to eq("a7f3k2xy")
      expect(parsed.resource_type).to eq("access_key")
      expect(parsed.resource_id).to eq("iam_v1_x")
    end

    it "rejects non-URN / foreign-service strings without raising" do
      [ "", "nope", "urn:cnfs:s3::acct:bucket/x" ].each do |bad|
        expect { described_class.parse(bad) }.not_to raise_error
      end
      expect(described_class.parse("urn:cnfs:s3::acct:bucket/x")).not_to be_valid
      expect(described_class.parse("nope")).not_to be_valid
    end
  end
end
