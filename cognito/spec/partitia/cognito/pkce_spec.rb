require "rails_helper"
require "base64"
require "digest"

RSpec.describe Partitia::Cognito::Pkce do
  it "produces a URL-safe, unpadded S256 challenge for a verifier" do
    verifier = described_class.verifier
    challenge = described_class.challenge(verifier)

    expect(challenge).not_to include("=", "+", "/")
    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    expect(challenge).to eq(expected)
  end

  it "generates distinct verifiers" do
    expect(described_class.verifier).not_to eq(described_class.verifier)
  end
end
