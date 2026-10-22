require "rails_helper"
require "net/http"

# Live discovery against pcm's Authentik (`pcm up authentik`, port 9000).
# Skipped unless AUTHENTIK_ISSUER is set and that issuer answers; the rest of the
# suite stubs the IdP with WebMock and never needs it. Run with:
#
#   AUTHENTIK_ISSUER=http://localhost:9000/application/o/<slug>/ bundle exec rspec spec/integration
RSpec.describe "Authentik (live, pcm)" do
  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!
  end

  def reachable?(issuer)
    uri = URI.join(issuer.end_with?("/") ? issuer : "#{issuer}/", ".well-known/openid-configuration")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 1, read_timeout: 2) do |http|
      http.get(uri.request_uri).is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end

  it "discovers the OIDC configuration from a running Authentik" do
    issuer = ENV["AUTHENTIK_ISSUER"]
    skip "set AUTHENTIK_ISSUER to run against pcm's Authentik" if issuer.blank?
    skip "#{issuer} is not reachable (pcm up authentik?)" unless reachable?(issuer)

    provider = Partitia::Cognito::Providers::Authentik.new(
      issuer: issuer,
      client_id: ENV.fetch("AUTHENTIK_CLIENT_ID", "test")
    )
    expect(provider.send(:discovery)).to include("authorization_endpoint", "token_endpoint", "jwks_uri")
  end
end
