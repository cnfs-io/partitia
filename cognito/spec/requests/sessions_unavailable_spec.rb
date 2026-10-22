require "rails_helper"

# When the IdP can't be reached (Authentik down, DNS, TLS, timeout, a non-200
# discovery), sign-in answers a plain 503 instead of a bare 500. Token
# verification failures keep their redirect-with-flash behavior.
RSpec.describe "broker sessions when the IdP is unreachable", :logs, type: :request do
  let(:discovery_url) { "#{OidcHelpers::ISSUER}/.well-known/openid-configuration" }
  let(:message) { "Sign-in is unavailable: the identity provider can't be reached." }

  before do
    Partitia::Cognito.provider = oidc_provider
    Partitia::Cognito.after_sign_in_path = "/home"
    Partitia::Cognito.after_sign_out_path = "/home"
  end

  def payloads_for(name)
    out = []
    callback = ->(_name, _start, _finish, _id, payload) { out << payload }
    ActiveSupport::Notifications.subscribed(callback, name) { yield }
    out
  end

  describe "GET /auth/login" do
    {
      "connection refused" => ->(stub) { stub.to_raise(Errno::ECONNREFUSED) },
      "a timeout" => ->(stub) { stub.to_timeout },
      "a DNS failure" => ->(stub) { stub.to_raise(SocketError.new("getaddrinfo: nodename nor servname provided")) },
      "an SSL error" => ->(stub) { stub.to_raise(OpenSSL::SSL::SSLError) },
      "a non-200 discovery response" => ->(stub) { stub.to_return(status: 502) }
    }.each do |failure, arrange|
      it "answers 503 on #{failure}" do
        arrange.call(stub_request(:get, discovery_url))

        get "/auth/login", headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:service_unavailable)
        expect(response.media_type).to eq("text/html")
        expect(response.body).to include(ERB::Util.html_escape(message))
      end
    end

    it "falls back to plain text for a non-HTML client" do
      stub_request(:get, discovery_url).to_raise(Errno::ECONNREFUSED)

      get "/auth/login", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:service_unavailable)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to eq(message)
    end

    it "logs a warning naming the issuer host, never a secret" do
      stub_request(:get, discovery_url).to_raise(Errno::ECONNREFUSED)

      get "/auth/login"

      warns = captured_log.at(:warn).join("\n")
      expect(warns).to include("sign-in unavailable").and include("idp.example")
      expect(captured_log.joined).not_to include("secret")
    end

    it "records outcome=idp_unavailable on the login_start event" do
      stub_request(:get, discovery_url).to_raise(Errno::ECONNREFUSED)

      payloads = payloads_for("partitia_cognito.sessions_controller.login_start") { get "/auth/login" }

      expect(payloads.first).to include(outcome: "idp_unavailable")
    end
  end

  describe "GET /auth/callback" do
    # Login succeeds (discovery reachable), then the IdP goes away before the
    # callback's code exchange. The provider caches discovery, so the token
    # endpoint is what fails.
    def start_login
      stub_oidc_discovery
      get "/auth/login"
      Rack::Utils.parse_query(URI(response.location).query)
    end

    before { Partitia::Cognito.identity_resolver = ->(*) { raise "must not resolve" } }

    it "answers 503 when the token endpoint refuses the connection" do
      q = start_login
      stub_request(:post, "#{OidcHelpers::ISSUER}/token").to_raise(Errno::ECONNREFUSED)

      payloads = payloads_for("partitia_cognito.sessions_controller.callback") do
        get "/auth/callback", params: { code: "c", state: q["state"] }
      end

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include(ERB::Util.html_escape(message))
      expect(payloads.first).to include(outcome: "idp_unavailable")
    end

    it "answers 503 when the JWKS can't be fetched during verification" do
      q = start_login
      stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))
      stub_request(:get, "#{OidcHelpers::ISSUER}/jwks").to_raise(Errno::ECONNREFUSED)

      get "/auth/callback", params: { code: "c", state: q["state"] }

      expect(response).to have_http_status(:service_unavailable)
    end

    it "still redirects with a flash when verification fails (not swallowed into a 503)" do
      q = start_login
      stub_token_endpoint(id_token: id_token(nonce: "tampered"))

      get "/auth/callback", params: { code: "c", state: q["state"] }

      expect(response).to redirect_to("/home")
    end
  end
end
