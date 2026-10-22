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
end
