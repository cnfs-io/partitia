require "rails_helper"
require "partitia/tenanted/telemetry_middleware"

# §1a: the opt-in outer-request-span middleware. Resolves the subdomain at the
# Rack edge (pure parsing, no DB) and emits one
# partitia_tenanted.telemetry_middleware.request notification wrapping the downstream
# call. Asserted at the notification layer — partitia-telemetry turns it into the
# outer span; baggage propagation needs the SDK and is exercised end-to-end
# separately.
RSpec.describe Partitia::Tenanted::TelemetryMiddleware do
  let(:downstream) { ->(_env) { [ 200, {}, [ "ok" ] ] } }
  subject(:middleware) { described_class.new(downstream) }

  def env_for(host)
    Rack::MockRequest.env_for("http://#{host}/dashboard", "REQUEST_METHOD" => "GET")
  end

  def request_payloads
    payloads = []
    callback = ->(_name, _start, _finish, _id, payload) { payloads << payload }
    ActiveSupport::Notifications.subscribed(
      callback, "partitia_tenanted.telemetry_middleware.request"
    ) { yield }
    payloads
  end

  it "emits a request event with http + subdomain attributes and calls through" do
    status = nil
    payloads = request_payloads do
      status, = middleware.call(env_for("acme.example.com"))
    end

    expect(status).to eq(200)
    expect(payloads.size).to eq(1)
    expect(payloads.first).to include(
      http_method: "GET", path: "/dashboard",
      host: "acme.example.com", subdomain: "acme"
    )
  end

  it "resolves a nil subdomain on the bare domain" do
    payloads = request_payloads { middleware.call(env_for("example.com")) }

    expect(payloads.first).to include(subdomain: nil)
  end

  it "degrades to nil subdomain (no 500) when the resolver raises" do
    allow(Partitia::Tenanted.tenant_resolver).to receive(:call).and_raise("boom")

    status = nil
    payloads = request_payloads do
      status, = middleware.call(env_for("acme.example.com"))
    end

    expect(status).to eq(200)
    expect(payloads.first).to include(subdomain: nil)
  end
end
