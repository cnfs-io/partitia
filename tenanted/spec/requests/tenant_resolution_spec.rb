require "rails_helper"

# WS3/WS6: request-level tenant resolution — subdomain -> Tenant lookup ->
# with_tenant(handle) — and the three-layer not-found seam.
RSpec.describe "tenant resolution", type: :request do
  it "resolves a known subdomain to its handle and runs the action in that context" do
    tenant = create_tenant!(subdomain: "acme")

    get "/probe", headers: { "HOST" => "acme.example.com" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("probe: #{tenant.handle}")
  end

  describe "unknown subdomain (not-found seam)" do
    it "falls back to a plain 404 by default" do
      get "/probe", headers: { "HOST" => "nope.example.com" }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Tenant 'nope' not found")
    end

    it "uses the configured tenant_not_found_handler when set" do
      CnfsTenanted.tenant_not_found_handler = ->(name) { render plain: "handler: #{name}", status: :not_found }

      get "/probe", headers: { "HOST" => "nope.example.com" }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq("handler: nope")
    end

    it "lets a controller override of #tenant_not_found win" do
      CnfsTenanted.tenant_not_found_handler = ->(name) { render plain: "handler: #{name}", status: :not_found }

      get "/probe-override", headers: { "HOST" => "nope.example.com" }

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq("override: nope")
    end
  end
end
