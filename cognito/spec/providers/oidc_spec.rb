require "rails_helper"

RSpec.describe Partitia::Cognito::Providers::Oidc do
  subject(:provider) { oidc_provider }

  before { stub_oidc_discovery }

  describe "#verify" do
    it "returns an Assertion with the expected fields for a valid token" do
      assertion = provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)

      expect(assertion).to be_a(Partitia::Cognito::Assertion)
      expect(assertion.issuer).to eq(OidcHelpers::ISSUER)
      expect(assertion.subject).to eq("idp-sub-1")
      expect(assertion.email).to eq("user@example.com")
      expect(assertion.email_verified).to be(true)
      expect(assertion.name).to eq("Test User")
      expect(assertion.claims["aud"]).to eq(OidcHelpers::CLIENT_ID)
    end

    it "rejects a bad signature (token signed by a different key)" do
      other_key = OpenSSL::PKey::RSA.generate(2048)
      token = id_token(key: other_key)
      expect { provider.verify(id_token: token, nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "rejects an expired token" do
      token = id_token(exp: Time.now.to_i - 60)
      expect { provider.verify(id_token: token, nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "rejects a wrong issuer" do
      token = id_token(iss: "https://evil.example")
      expect { provider.verify(id_token: token, nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "matches the issuer exactly as configured, trailing slash and all (Authentik's)" do
      slashed = oidc_provider(issuer: "#{OidcHelpers::ISSUER}/")
      token = id_token(iss: "#{OidcHelpers::ISSUER}/")
      expect(slashed.verify(id_token: token, nonce: OidcHelpers::NONCE).issuer).to eq("#{OidcHelpers::ISSUER}/")

      expect { slashed.verify(id_token: id_token, nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "rejects a wrong audience" do
      token = id_token(aud: "someone-else")
      expect { provider.verify(id_token: token, nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "rejects a mismatched nonce" do
      expect { provider.verify(id_token: id_token, nonce: "different-nonce") }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "rejects a missing nonce claim" do
      token = id_token(nonce: nil)
      expect { provider.verify(id_token: token, nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "rejects a malformed token" do
      expect { provider.verify(id_token: "not.a.jwt", nonce: OidcHelpers::NONCE) }
        .to raise_error(Partitia::Cognito::Providers::VerificationError)
    end

    it "refetches the JWKS when the kid is unknown, then verifies" do
      # First JWKS response lacks the signing kid; the second (after refetch) has it.
      empty = { "keys" => [] }
      stub_request(:get, "#{OidcHelpers::ISSUER}/jwks")
        .to_return(
          { status: 200, headers: { "Content-Type" => "application/json" }, body: empty.to_json },
          { status: 200, headers: { "Content-Type" => "application/json" }, body: jwks.to_json }
        )

      assertion = provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)
      expect(assertion.subject).to eq("idp-sub-1")
    end
  end

  describe "#authorization_url" do
    it "builds an auth-code + PKCE (S256) URL with state and nonce" do
      url = provider.authorization_url(
        redirect_uri: "https://host/auth/callback",
        state: "st", nonce: "no", code_challenge: "cc"
      )
      query = Rack::Utils.parse_query(URI(url).query)

      expect(url).to start_with("#{OidcHelpers::ISSUER}/authorize")
      expect(query).to include(
        "response_type" => "code",
        "client_id" => OidcHelpers::CLIENT_ID,
        "state" => "st",
        "nonce" => "no",
        "code_challenge" => "cc",
        "code_challenge_method" => "S256"
      )
    end
  end
end
