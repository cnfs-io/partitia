require "rails_helper"

# §1b: the switch_tenant around_action emits one
# partitia_tenanted.tenant_resolution.switch notification per request, whose payload
# makes the three resolution outcomes distinct (and carries the resolved handle).
# Asserted at the notification layer — no OTel SDK needed — exactly what
# partitia-telemetry would turn into a span.
RSpec.describe "tenant resolution instrumentation", type: :request do
  # Collect the payloads of every switch event fired during the block. Uses the
  # auto-unsubscribing block form so no subscriber leaks between examples.
  def switch_payloads
    payloads = []
    callback = ->(_name, _start, _finish, _id, payload) { payloads << payload }
    ActiveSupport::Notifications.subscribed(
      callback, "partitia_tenanted.tenant_resolution.switch"
    ) { yield }
    payloads
  end

  it "records outcome=switched with the resolved handle on a known subdomain" do
    tenant = create_tenant!(subdomain: "acme")

    payloads = switch_payloads do
      get "/probe", headers: { "HOST" => "acme.example.com" }
    end

    expect(response).to have_http_status(:ok)
    expect(payloads.size).to eq(1)
    expect(payloads.first).to include(
      subdomain: "acme", outcome: "switched", handle: tenant.handle
    )
  end

  it "records outcome=untenanted on the bare domain (no subdomain)" do
    payloads = switch_payloads do
      get "/probe", headers: { "HOST" => "example.com" }
    end

    expect(response).to have_http_status(:ok)
    expect(payloads.first).to include(subdomain: nil, outcome: "untenanted")
    expect(payloads.first).not_to have_key(:handle)
  end

  it "records outcome=not_found for a resolved-but-unknown subdomain" do
    payloads = switch_payloads do
      get "/probe", headers: { "HOST" => "nope.example.com" }
    end

    expect(response).to have_http_status(:not_found)
    expect(payloads.first).to include(subdomain: "nope", outcome: "not_found")
    expect(payloads.first).not_to have_key(:handle)
  end
end
