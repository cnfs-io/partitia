require "rails_helper"

RSpec.describe Iam::AccessKeyId do
  let(:handle) { "a7f3k2xy" }

  describe ".generate / .parse round-trip" do
    it "produces a parseable, valid, self-describing key" do
      key = described_class.generate(account_handle: handle)

      expect(key).to start_with("iam_v1_#{handle}_")
      parsed = described_class.parse(key)
      expect(parsed).to be_valid
      expect(parsed.version).to eq("v1")
      expect(parsed.account_handle).to eq(handle)
      expect(parsed.random.length).to eq(described_class::RANDOM_LEN)
      expect(parsed.checksum.length).to eq(described_class::CHECKSUM_LEN)
    end

    it "recovers the account handle by plain split (no obfuscation)" do
      key = described_class.generate(account_handle: handle)
      expect(key.split("_")[2]).to eq(handle)
    end
  end

  describe "tamper detection" do
    it "rejects a key whose body was altered (checksum mismatch)" do
      key = described_class.generate(account_handle: handle)
      # Flip a character in the random segment (keep it in-alphabet).
      tampered = key.dup
      i = "iam_v1_#{handle}_".length
      tampered[i] = tampered[i] == "q" ? "r" : "q"

      expect(described_class.parse(tampered)).not_to be_valid
      expect(described_class.valid?(tampered)).to be(false)
    end

    it "rejects malformed / foreign keys without raising" do
      [ "", "nope", "iam_v1_#{handle}", "aws_v1_#{handle}_abcdef", "iam__#{handle}_abcdef" ].each do |bad|
        expect { described_class.parse(bad) }.not_to raise_error
        expect(described_class.valid?(bad)).to be(false)
      end
    end
  end

  it "carries the greppable fixed prefix and version position" do
    key = described_class.generate(account_handle: handle)
    expect(key).to match(/\Aiam_v1_/)
  end
end
