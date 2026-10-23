require "rails_helper"

# D6: a sign-in lands in the database the Rack layer selected. Where it selected
# none (an unknown subdomain, the apex) tenanted's before_sign_in hook stops
# cognito's flow before any IdP round trip.
RSpec.describe "sign-in where no database is selected", type: :request do
  before do
    wire_integration!
    Partitia::Tenanted.tenant_not_found_handler = ->(name) do
      flash[:unknown_tenant] = name
      redirect_to tenant_unknown_path
    end
  end

  it "is registered with partitia-cognito" do
    expect(Partitia::Cognito.before_sign_in).to include(Partitia::Tenanted::SIGN_IN_NEEDS_DATABASE)
  end

  it "sends an unknown subdomain to /tenant-unknown, not to the IdP" do
    host! "bogus.example.com"

    get "/auth/login"
    expect(response).to redirect_to("http://bogus.example.com/tenant-unknown")

    follow_redirect!
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("bogus")
    expect(response.body).to include('href="http://example.com/"') # no root route needed
  end

  it "refuses the callback on an unknown subdomain (no 500)" do
    host! "bogus.example.com"

    get "/auth/callback", params: { code: "c", state: "s" }
    expect(response).to redirect_to("http://bogus.example.com/tenant-unknown")
  end

  it "answers 404 on the apex, before the IdP, for login and callback" do
    host! "example.com"

    get "/auth/login"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("sign in at your workspace's address")

    get "/auth/callback", params: { code: "c", state: "s" }
    expect(response).to have_http_status(:not_found)
  end

  it "still starts a sign-in on a known tenant's subdomain" do
    create_tenant!(subdomain: "acme")
    host! "acme.example.com"

    get "/auth/login"
    expect(response.location).to start_with("#{OidcHelpers::ISSUER}/authorize")
  end

  it "still lets the host's platform entry point (reserved database) through" do
    provision_platform!
    host! "example.com"

    get "/platform/login"
    follow_redirect!
    expect(response.location).to start_with("#{OidcHelpers::ISSUER}/authorize")
  end
end
