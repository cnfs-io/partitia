require "rails_helper"

# §2: the broker's SessionsController emits partitia_cognito.sessions_controller.<verb>
# notifications; #callback records the exact resolution outcome on its payload so
# a login's success/failure reason is visible in the trace. Asserted at the
# notification layer over the real request flow.
RSpec.describe "broker sessions instrumentation", type: :request do
  before do
    stub_oidc_discovery
    Partitia::Cognito.provider = oidc_provider
    Partitia::Cognito.after_sign_in_path = "/home"
    Partitia::Cognito.after_sign_out_path = "/home"
  end

  def start_login(params = {})
    get "/auth/login", params: params
    Rack::Utils.parse_query(URI(response.location).query)
  end

  def callback_payloads
    out = []
    callback = ->(_name, _start, _finish, _id, payload) { out << payload }
    ActiveSupport::Notifications.subscribed(
      callback, "partitia_cognito.sessions_controller.callback"
    ) { yield }
    out
  end

  it "records outcome=success and the policy on a completed login" do
    Partitia::Cognito.policy_resolver = ->(_request) { :jit }
    Partitia::Cognito.identity_resolver =
      ->(_assertion, _policy, _link) { FakeResult.new(true, FakePrincipal.new(4242), nil) }

    q = start_login
    stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

    payloads = callback_payloads do
      get "/auth/callback", params: { code: "auth-code", state: q["state"] }
    end

    expect(payloads.size).to eq(1)
    expect(payloads.first).to include(outcome: "success", policy: "jit")
  end

  it "records outcome=invalid_state and never exchanges the code on a bad state" do
    Partitia::Cognito.identity_resolver = ->(*) { raise "resolver must not be called" }
    start_login

    payloads = callback_payloads do
      get "/auth/callback", params: { code: "c", state: "wrong-state" }
    end

    expect(payloads.first).to include(outcome: "invalid_state")
  end

  it "records outcome=verification_failed on a tampered token, leaking nothing" do
    Partitia::Cognito.identity_resolver = ->(*) { raise "must not resolve" }

    q = start_login
    stub_token_endpoint(id_token: id_token(nonce: "tampered"))

    payloads = callback_payloads do
      get "/auth/callback", params: { code: "c", state: q["state"] }
    end

    expect(payloads.first).to include(outcome: "verification_failed")
  end

  it "records the resolver failure reason as the outcome" do
    Partitia::Cognito.identity_resolver = ->(*) { FakeResult.new(false, nil, "unknown_identity") }

    q = start_login
    stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

    payloads = callback_payloads do
      get "/auth/callback", params: { code: "c", state: q["state"] }
    end

    expect(payloads.first).to include(outcome: "unknown_identity")
  end

  # The cardinality/PII guard over the controller spans: a completed login (which
  # resolves a principal and establishes a session) must leave no sensitive field
  # on any partitia-cognito span. Forbidden set read from the redaction config.
  it "attaches no sensitive field to any span across a full login (list from RedactionConfig)" do
    sensitive = Partitia::Support::RedactionConfig.sensitive_fields
    Partitia::Cognito.policy_resolver = ->(_request) { :jit }
    Partitia::Cognito.identity_resolver =
      ->(_assertion, _policy, _link) { FakeResult.new(true, FakePrincipal.new(4242), nil) }

    q = start_login
    stub_token_endpoint(id_token: id_token(nonce: q["nonce"]))

    captured = []
    callback = ->(name, _s, _f, _id, payload) { captured << [ name, payload ] }
    ActiveSupport::Notifications.subscribed(callback, /\Apartitia_cognito\./) do
      get "/auth/callback", params: { code: "auth-code", state: q["state"] }
    end

    expect(captured).not_to be_empty
    captured.each do |name, payload|
      leaked = payload.keys.map(&:to_sym) & sensitive
      expect(leaked).to be_empty, "#{name} leaked sensitive attribute(s): #{leaked.inspect}"
    end
  end
end
