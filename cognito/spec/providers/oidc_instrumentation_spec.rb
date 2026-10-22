require "rails_helper"

# The provider classes live 3 levels deep (Partitia::Cognito::Providers::Oidc), so
# their instrument helper pins the flat "partitia_cognito" component with the
# concrete provider as subject — events are partitia_cognito.oidc.<verb>. Asserted at
# the notification layer (no OTel SDK); partitia-telemetry turns these into spans.
RSpec.describe Partitia::Cognito::Providers::Oidc, "instrumentation" do
  subject(:provider) { oidc_provider }

  before { stub_oidc_discovery }

  def payloads_for(name)
    out = []
    callback = ->(_name, _start, _finish, _id, payload) { out << payload }
    ActiveSupport::Notifications.subscribed(callback, name) { yield }
    out
  end

  it "emits partitia_cognito.oidc.verify with issuer and outcome=verified, never the subject" do
    payloads = payloads_for("partitia_cognito.oidc.verify") do
      provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)
    end

    expect(payloads.size).to eq(1)
    expect(payloads.first).to include(issuer: OidcHelpers::ISSUER, outcome: "verified")
    # The IdP subject (sub) is PII + a cardinality bomb — never a span attribute.
    expect(payloads.first).not_to have_key(:subject)
  end

  it "records a closed-vocabulary outcome on each verify failure path" do
    cases = {
      "nonce_mismatch" => -> { provider.verify(id_token: id_token, nonce: "different-nonce") },
      "unknown_kid"    => -> { provider.verify(id_token: id_token(kid: "no-such-kid"), nonce: OidcHelpers::NONCE) },
      "bad_signature"  => -> { provider.verify(id_token: id_token(key: OpenSSL::PKey::RSA.generate(2048)), nonce: OidcHelpers::NONCE) },
      "expired"        => -> { provider.verify(id_token: id_token(exp: Time.now.to_i - 60), nonce: OidcHelpers::NONCE) }
    }

    cases.each do |expected_outcome, drive|
      payloads = payloads_for("partitia_cognito.oidc.verify") do
        expect { drive.call }.to raise_error(Partitia::Cognito::Providers::VerificationError)
      end
      expect(payloads.first).to include(outcome: expected_outcome)
    end
  end

  it "emits a nested partitia_cognito.oidc.signing_key event carrying the kid" do
    payloads = payloads_for("partitia_cognito.oidc.signing_key") do
      provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)
    end

    expect(payloads.first).to include(kid: be_a(String))
    expect(payloads.first).not_to include(rotated: true)
  end

  it "marks rotated=true on the signing_key event when the kid triggers a JWKS refetch" do
    empty = { "keys" => [] }
    stub_request(:get, "#{OidcHelpers::ISSUER}/jwks").to_return(
      { status: 200, headers: { "Content-Type" => "application/json" }, body: empty.to_json },
      { status: 200, headers: { "Content-Type" => "application/json" }, body: jwks.to_json }
    )

    payloads = payloads_for("partitia_cognito.oidc.signing_key") do
      provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)
    end

    expect(payloads.first).to include(rotated: true)
  end

  it "emits partitia_cognito.oidc.http egress events with method, status, and a bounded endpoint (never the url)" do
    payloads = payloads_for("partitia_cognito.oidc.http") do
      provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)
    end

    expect(payloads).not_to be_empty
    expect(payloads.map { |p| p[:method] }).to all(eq("GET"))
    expect(payloads.map { |p| p[:status] }).to all(eq(200))
    # The full URL is a cardinality risk — replaced by a bounded endpoint label.
    expect(payloads.map { |p| p[:endpoint] }).to all(be_in(%w[discovery jwks token]))
    expect(payloads.map(&:keys).flatten).not_to include(:url)
  end

  it "emits partitia_cognito.oidc.exchange_code with outcome=ok and a token-endpoint http POST" do
    stub_token_endpoint(id_token: id_token)

    exchange = payloads_for("partitia_cognito.oidc.exchange_code") do
      @http = payloads_for("partitia_cognito.oidc.http") do
        provider.exchange_code(code: "auth-code", redirect_uri: "https://app.test/cb", code_verifier: "v")
      end
    end

    expect(exchange.first).to include(outcome: "ok")
    post = @http.find { |p| p[:method] == "POST" }
    expect(post).to include(endpoint: "token", status: 200)
  end

  # The cardinality/PII guard (WS1.5): no partitia-cognito span may carry a sensitive
  # / high-cardinality attribute. The forbidden set is READ FROM the redaction
  # config (Plan 006), so a new sensitive field is enforced here automatically.
  it "attaches no sensitive field to any partitia_cognito span (list read from RedactionConfig)" do
    sensitive = Partitia::Support::RedactionConfig.sensitive_fields
    stub_token_endpoint(id_token: id_token)

    captured = []
    callback = ->(name, _s, _f, _id, payload) { captured << [ name, payload ] }
    ActiveSupport::Notifications.subscribed(callback, /\Apartitia_cognito\./) do
      provider.verify(id_token: id_token, nonce: OidcHelpers::NONCE)
      provider.exchange_code(code: "c", redirect_uri: "https://app.test/cb", code_verifier: "v")
    end

    captured.each do |name, payload|
      leaked = payload.keys.map(&:to_sym) & sensitive
      expect(leaked).to be_empty, "#{name} leaked sensitive attribute(s): #{leaked.inspect}"
    end
  end
end
