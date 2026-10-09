require "rails_helper"

# §3: the Iam::Authenticatable concern is a mixin, so its notifications must be
# composed under the gem's own component (cnfs_iam.authenticatable.*) rather than
# the host controller's class. Asserted over the real request flow.
RSpec.describe "authentication instrumentation", type: :request do
  def payloads_for(name)
    out = []
    callback = ->(_name, _start, _finish, _id, payload) { out << payload }
    ActiveSupport::Notifications.subscribed(callback, name) { yield }
    out
  end

  it "emits cnfs_iam.authenticatable.authenticate_request with authenticated=false when anonymous" do
    payloads = payloads_for("cnfs_iam.authenticatable.authenticate_request") { get "/whoami" }

    expect(payloads.first).to include(authenticated: false)
  end

  it "records authenticated=true once a principal is in the session" do
    principal = Iam::HumanPrincipal.create!(name: "alice")
    post "/sign_in", params: { id: principal.id }

    payloads = payloads_for("cnfs_iam.authenticatable.authenticate_request") { get "/whoami" }

    expect(payloads.first).to include(authenticated: true)
  end

  it "records outcome=denied on the authz gate for an anonymous request" do
    payloads = payloads_for("cnfs_iam.authenticatable.authz_gate") { get "/protected" }

    expect(response).to have_http_status(:unauthorized)
    expect(payloads.first).to include(outcome: "denied")
  end

  it "records outcome=allowed on the authz gate for an authenticated request" do
    principal = Iam::HumanPrincipal.create!(name: "alice")
    post "/sign_in", params: { id: principal.id }

    payloads = payloads_for("cnfs_iam.authenticatable.authz_gate") { get "/protected" }

    expect(response).to have_http_status(:ok)
    expect(payloads.first).to include(outcome: "allowed")
  end
end
