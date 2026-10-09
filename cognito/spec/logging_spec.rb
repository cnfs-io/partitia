require "rails_helper"

# Plan 005 WS4: diagnostic logging is behavior, tested with a capturing backend
# (never stdout). Covers tag correctness (including the deeply-nested provider),
# level routing across all four levels, redaction of token/code/client_secret,
# block-form laziness, and the default-level silence contract. Reuses the
# existing WebMock OIDC harness — no container, no network.
RSpec.describe "cnfs_cognito diagnostic logging", :logs do
  before { stub_oidc_discovery }

  describe "provider tag correctness" do
    # The regression guard: CnfsCognito::Providers::Oidc is three namespaces
    # deep, yet component_tag collapses it to the flat gem tag. No
    # cnfs_cognito/providers tag can occur.
    it "tags a nested-provider line [cnfs_cognito]" do
      oidc_provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)

      expect(captured_log.messages).not_to be_empty
      expect(captured_log.messages).to all(start_with("[cnfs_cognito]"))
      expect(captured_log.joined).to include("discovery: fetching")
    end
  end

  describe "level routing" do
    it "logs a discovery HTTP non-2xx at error (real fault)" do
      stub_request(:get, "#{OidcHelpers::ISSUER}/.well-known/openid-configuration").to_return(status: 500)

      expect do
        oidc_provider.authorization_url(redirect_uri: "https://h/cb", state: "s", nonce: "n", code_challenge: "c")
      end.to raise_error(CnfsCognito::Providers::VerificationError)

      expect(captured_log.at(:error).join("\n")).to match(%r{http GET .+ -> 500})
    end

    it "logs a verify failure at warn (expected security outcome, not error)" do
      token = id_token(nonce: "real-nonce")

      expect { oidc_provider.verify(id_token: token, nonce: "different-nonce") }
        .to raise_error(CnfsCognito::Providers::VerificationError)

      expect(captured_log.at(:warn).join("\n")).to include("verify failed")
      expect(captured_log.at(:error)).to be_empty
    end

    it "logs a discovery fetch at debug" do
      oidc_provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)

      expect(captured_log.at(:debug).join("\n")).to include("discovery: fetching")
    end
  end

  describe "redaction (provider layer)" do
    it "never logs the id_token on a failed verify" do
      token = id_token(nonce: "real-nonce")

      oidc_provider.verify(id_token: token, nonce: "mismatch") rescue nil

      expect(captured_log.joined).not_to include(token)
    end
  end

  describe "block-form laziness" do
    it "does not evaluate a debug block when the tag level is info" do
      CnfsSupport::Logging.levels["cnfs_cognito"] = :info
      logger = CnfsSupport::Logging.build_for("CnfsCognito::Providers::Oidc")

      expect { logger.debug { raise "block must not be evaluated at :info" } }.not_to raise_error
    end
  end

  # The controller + full callback flow. cognito infers :request by location, so
  # declare it explicitly here since this file is not under spec/requests.
  describe "sessions controller", type: :request do
    before do
      CnfsCognito.provider = oidc_provider
      CnfsCognito.after_sign_in_path = "/home"
      CnfsCognito.after_sign_out_path = "/home"
    end

    def start_login(params = {})
      get "/auth/login", params: params
      Rack::Utils.parse_query(URI(response.location).query)
    end

    it "logs sign-in ok at info under [cnfs_cognito], id only" do
      CnfsCognito.identity_resolver = ->(*) { FakeResult.new(true, FakePrincipal.new(4242), nil) }
      q = start_login
      stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

      get "/auth/callback", params: { code: "auth-code", state: q["state"] }

      expect(captured_log.at(:info).join("\n")).to include("sign-in ok: principal id=4242")
      expect(captured_log.tagged("cnfs_cognito")).to include(a_string_matching(/sign-in ok/))
    end

    it "logs a state mismatch at warn" do
      CnfsCognito.identity_resolver = ->(*) { raise "resolver must not be called" }
      start_login

      get "/auth/callback", params: { code: "c", state: "wrong-state" }

      expect(captured_log.at(:warn).join("\n")).to include("callback: state mismatch")
    end

    it "never logs the id_token, code, or client_secret across the callback + exchange" do
      secret_sentinel = "sentinel-client-secret"
      CnfsCognito.provider = CnfsCognito::Providers::Oidc.new(
        issuer: OidcHelpers::ISSUER, client_id: OidcHelpers::CLIENT_ID, client_secret: secret_sentinel
      )
      CnfsCognito.identity_resolver = ->(*) { FakeResult.new(true, FakePrincipal.new(1), nil) }

      q = start_login
      token = id_token(nonce: q["nonce"])
      stub_token_endpoint(id_token: token)

      get "/auth/callback", params: { code: "sentinel-auth-code", state: q["state"] }

      joined = captured_log.joined
      expect(joined).not_to include(token)
      expect(joined).not_to include("sentinel-auth-code")
      expect(joined).not_to include(secret_sentinel)
    end

    it "at :info a happy callback emits only the info ledger, no debug spam" do
      CnfsSupport::Logging.levels[:default] = :info
      CnfsCognito.identity_resolver = ->(*) { FakeResult.new(true, FakePrincipal.new(7), nil) }
      q = start_login
      stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

      get "/auth/callback", params: { code: "c", state: q["state"] }

      expect(captured_log.at(:debug)).to be_empty
      expect(captured_log.at(:info)).to contain_exactly("[cnfs_cognito] sign-in ok: principal id=7")
    end
  end
end
