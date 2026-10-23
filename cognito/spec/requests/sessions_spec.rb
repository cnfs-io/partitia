require "rails_helper"

RSpec.describe "broker sessions", type: :request do
  before do
    stub_oidc_discovery
    Partitia::Cognito.provider = oidc_provider
    Partitia::Cognito.after_sign_in_path = "/home"
    Partitia::Cognito.after_sign_out_path = "/home"
  end

  # Start a login and return the auth params the broker sent to the IdP (state
  # and nonce are echoed in the authorization URL). The session cookie carrying
  # the matching stash persists into the follow-up callback request.
  def start_login(params = {})
    get "/auth/login", params: params
    Rack::Utils.parse_query(URI(response.location).query)
  end

  describe "GET /auth/login" do
    it "redirects to the provider with state, nonce and PKCE (S256) params" do
      get "/auth/login"

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("#{OidcHelpers::ISSUER}/authorize")
      q = Rack::Utils.parse_query(URI(response.location).query)
      expect(q["state"]).to be_present
      expect(q["nonce"]).to be_present
      expect(q["code_challenge"]).to be_present
      expect(q["code_challenge_method"]).to eq("S256")
    end
  end

  describe "GET /auth/callback (happy path)" do
    it "resolves the assertion and establishes the session" do
      seen = {}
      Partitia::Cognito.identity_resolver = ->(assertion, policy, link_token) do
        seen[:policy] = policy
        seen[:link_token] = link_token
        seen[:subject] = assertion.subject
        FakeResult.new(true, FakePrincipal.new(4242), nil)
      end

      q = start_login
      stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

      get "/auth/callback", params: { code: "auth-code", state: q["state"] }

      expect(response).to redirect_to("/home")
      expect(seen).to include(policy: :invite_only, subject: "idp-sub-1")
    end

    it "passes the stashed link_token and request-derived policy to the resolver" do
      Partitia::Cognito.policy_resolver = ->(_request) { :jit }
      captured = {}
      Partitia::Cognito.identity_resolver = ->(_assertion, policy, link_token) do
        captured[:policy] = policy
        captured[:link_token] = link_token
        FakeResult.new(true, FakePrincipal.new(1), nil)
      end

      q = start_login(link_token: "invite-123")
      stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

      get "/auth/callback", params: { code: "c", state: q["state"] }

      expect(captured).to eq(policy: :jit, link_token: "invite-123")
    end
  end

  describe "GET /auth/callback (rejections)" do
    it "rejects a mismatched state without calling the resolver or exchanging a code" do
      Partitia::Cognito.identity_resolver = ->(*) { raise "resolver must not be called" }
      start_login # establishes a real state in the session stash

      # No token endpoint stub: if the code were exchanged, WebMock would error.
      get "/auth/callback", params: { code: "c", state: "wrong-state" }
      follow_redirect!

      expect(response.body).to include(I18n.t("partitia_cognito.sessions.failures.invalid_state"))
    end

    it "on resolver failure sets no session and flashes the keyed reason" do
      Partitia::Cognito.identity_resolver = ->(*) { FakeResult.new(false, nil, "unknown_identity") }

      q = start_login
      stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

      get "/auth/callback", params: { code: "c", state: q["state"] }
      follow_redirect!

      expect(response.body).to include(I18n.t("partitia_cognito.sessions.failures.unknown_identity"))
    end

    it "flashes a generic failure when verification fails (bad nonce), leaking nothing" do
      Partitia::Cognito.identity_resolver = ->(*) { raise "must not resolve" }

      q = start_login
      # Token carries a nonce that won't match the stash -> verification fails.
      stub_token_endpoint(id_token: id_token(nonce: "tampered"))
      # keep q referenced for state below
      get "/auth/callback", params: { code: "c", state: q["state"] }
      follow_redirect!

      expect(response.body).to include(I18n.t("partitia_cognito.sessions.failures.verification_failed"))
    end
  end

  describe "DELETE /auth/logout" do
    it "drops the session and redirects to the sign-out path" do
      delete "/auth/logout"
      expect(response).to redirect_to("/home")
    end
  end

  describe "before_sign_in hooks" do
    it "runs before /auth/login and stops the flow when one redirects (no IdP round trip)" do
      seen = []
      Partitia::Cognito.before_sign_in << -> { seen << action_name }
      Partitia::Cognito.before_sign_in << -> { redirect_to "/elsewhere" }
      Partitia::Cognito.before_sign_in << -> { seen << :never }

      get "/auth/login"

      expect(response).to redirect_to("/elsewhere")
      expect(seen).to eq([ "new" ])
      expect(session[Partitia::Cognito::SessionsController::SESSION_STASH]).to be_nil
    end

    it "runs before /auth/callback and can render instead of resolving" do
      Partitia::Cognito.identity_resolver = ->(*) { raise "not reached" }
      Partitia::Cognito.before_sign_in << -> { render plain: "no sign-in here", status: :not_found }

      get "/auth/callback", params: { code: "c", state: "s" }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq("no sign-in here")
    end

    it "lets the sign-in proceed when no hook halts" do
      Partitia::Cognito.before_sign_in << -> { }

      get "/auth/login"

      expect(response.location).to start_with("#{OidcHelpers::ISSUER}/authorize")
    end
  end
end
