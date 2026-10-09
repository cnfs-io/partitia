require "jwt"
require "openssl"

# WebMock-backed OIDC harness (Plan 003 WS5): a real RSA keypair, a stubbed
# discovery document + JWKS (serving the public key), signed ID tokens minted
# with the private key, and a stubbed token endpoint. No container, no network.
module OidcHelpers
  ISSUER    = "https://idp.example".freeze
  CLIENT_ID = "test-client".freeze
  KID       = "test-key-1".freeze
  NONCE     = "test-nonce".freeze

  # Stable across the whole suite. The broker's provider is a boot-time
  # singleton that caches discovery + JWKS on first use, so the signing key must
  # not change between examples or a later token would fail signature
  # verification against the cached JWKS.
  def rsa_key
    OidcHelpers.shared_rsa_key
  end

  def self.shared_rsa_key
    @shared_rsa_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def jwks(key: rsa_key, kid: KID)
    { "keys" => [ JWT::JWK.new(key, kid: kid).export ] }
  end

  def stub_oidc_discovery(issuer: ISSUER, jwks_body: nil)
    stub_request(:get, "#{issuer}/.well-known/openid-configuration").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/authorize",
        token_endpoint: "#{issuer}/token",
        jwks_uri: "#{issuer}/jwks"
      }.to_json
    )
    stub_request(:get, "#{issuer}/jwks").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: (jwks_body || jwks).to_json
    )
  end

  def stub_token_endpoint(id_token:, issuer: ISSUER)
    stub_request(:post, "#{issuer}/token").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { id_token: id_token, token_type: "Bearer" }.to_json
    )
  end

  # Mint a signed ID token. Override any claim as a keyword; the reserved
  # keywords `key:`/`kid:` let a spec sign with the wrong key or an unknown kid.
  def id_token(**overrides)
    key = overrides.delete(:key) || rsa_key
    kid = overrides.delete(:kid) || KID

    claims = {
      iss: ISSUER,
      aud: CLIENT_ID,
      sub: "idp-sub-1",
      iat: Time.now.to_i,
      exp: Time.now.to_i + 300,
      nonce: NONCE,
      email: "user@example.com",
      email_verified: true,
      name: "Test User"
    }.merge(overrides)

    JWT.encode(claims, key, "RS256", { kid: kid })
  end

  def oidc_provider(issuer: ISSUER, client_id: CLIENT_ID)
    CnfsCognito::Providers::Oidc.new(issuer: issuer, client_id: client_id, client_secret: "secret")
  end
end

# A stand-in for Iam::Resolution's result, wired into the identity_resolver slot.
FakePrincipal = Struct.new(:id)
FakeResult = Struct.new(:ok, :principal, :failure_reason) do
  def success?
    ok
  end
end

RSpec.configure do |config|
  config.include OidcHelpers
end
