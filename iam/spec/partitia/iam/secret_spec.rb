require "rails_helper"

RSpec.describe Partitia::Iam::Secret do
  describe ".generate" do
    it "produces a greppable, high-entropy plaintext secret" do
      secret = described_class.generate
      expect(secret).to start_with("iam_secret_")
      expect(described_class.generate).not_to eq(secret)
    end
  end

  describe ".digest / .verify" do
    it "verifies the matching plaintext and rejects a wrong one" do
      secret = described_class.generate
      digest = described_class.digest(secret)

      expect(digest).not_to include(secret)          # plaintext is not stored
      expect(described_class.verify(secret, digest)).to be(true)
      expect(described_class.verify("iam_secret_wrong", digest)).to be(false)
    end

    it "is stable for the same plaintext+key (HMAC, not salted)" do
      expect(described_class.digest("x")).to eq(described_class.digest("x"))
    end

    it "returns false for blank inputs rather than raising" do
      expect(described_class.verify(nil, "d")).to be(false)
      expect(described_class.verify("s", nil)).to be(false)
    end

    it "changes the digest when the server-side hmac key changes" do
      digest = described_class.digest("x")
      original = Partitia::Iam.config.hmac_key
      Partitia::Iam.config.hmac_key = "a-different-key"
      expect(described_class.digest("x")).not_to eq(digest)
    ensure
      Partitia::Iam.config.hmac_key = original
    end
  end
end
