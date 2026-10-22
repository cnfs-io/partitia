require "rails_helper"

# WS5/WS6: the platform console guard on the tenant registry controller.
RSpec.describe "platform console guard", type: :request do
  it "denies access by default (an unconfigured console is closed)" do
    get "/tenants", headers: { "HOST" => "example.com" }
    expect(response).to have_http_status(:forbidden)
  end

  it "allows access when a permissive guard is configured" do
    CnfsTenanted.platform_console_guard = -> { } # no render/redirect -> proceed

    get "/tenants", headers: { "HOST" => "example.com" }

    expect(response).to have_http_status(:ok)
  end
end
