require "rails_helper"

# Partitia::Cognito::Config carries the provider connection DATA (issuer, client_id,
# client_secret, scopes) — the anyway_config surface, resolved from
# config/partitia_cognito.yml → credentials.partitia_cognito → ENV["PARTITIA_COGNITO_*"].
# (The behavioral slots on the Partitia::Cognito module are covered in config_spec.rb.)
RSpec.describe Partitia::Cognito::Config do
  after do
    described_class.reset_instance!
    ENV.delete("PARTITIA_COGNITO_ISSUER")
    ENV.delete("PARTITIA_COGNITO_CLIENT_ID")
    ENV.delete("PARTITIA_COGNITO_CLIENT_SECRET")
    ENV.delete("PARTITIA_COGNITO_CLIENT_TYPE")
  end

  it "defaults scopes to the OIDC baseline and leaves connection keys unset" do
    described_class.reset_instance!

    expect(described_class.scopes).to eq(%w[openid email profile])
    expect(described_class.issuer).to be_nil
    expect(described_class.client_id).to be_nil
    expect(described_class.client_secret).to be_nil
  end

  it "resolves the non-secret connection values from ENV" do
    ENV["PARTITIA_COGNITO_ISSUER"] = "https://idp.example.com/application/o/app"
    ENV["PARTITIA_COGNITO_CLIENT_ID"] = "public-client-id"
    described_class.reset_instance!

    expect(described_class.issuer).to eq("https://idp.example.com/application/o/app")
    expect(described_class.client_id).to eq("public-client-id")
  end

  it "resolves the client_secret (a secret) from ENV, never a source literal" do
    ENV["PARTITIA_COGNITO_CLIENT_SECRET"] = "secret-from-env"
    described_class.reset_instance!

    expect(described_class.client_secret).to eq("secret-from-env")
  end

  describe "client_type" do
    it "defaults to public, which sends no secret even when one is configured" do
      ENV["PARTITIA_COGNITO_CLIENT_SECRET"] = "secret-from-env"
      described_class.reset_instance!

      expect(described_class.client_type).to eq("public")
      expect(described_class.confidential?).to be(false)
      expect(described_class.token_secret).to be_nil
    end

    it "sends the client_secret for a confidential client" do
      ENV["PARTITIA_COGNITO_CLIENT_TYPE"] = "confidential"
      ENV["PARTITIA_COGNITO_CLIENT_SECRET"] = "secret-from-env"
      described_class.reset_instance!

      expect(described_class.token_secret).to eq("secret-from-env")
    end

    it "requires a client_secret for a confidential client" do
      ENV["PARTITIA_COGNITO_CLIENT_TYPE"] = "confidential"
      described_class.reset_instance!

      expect { described_class.token_secret }
        .to raise_error(Partitia::Cognito::ConfigurationError, /confidential but no client_secret/)
    end

    it "rejects an unknown client_type" do
      ENV["PARTITIA_COGNITO_CLIENT_TYPE"] = "secret"
      described_class.reset_instance!

      expect { described_class.confidential? }
        .to raise_error(Partitia::Cognito::ConfigurationError, /must be one of public, confidential/)
    end
  end
end
