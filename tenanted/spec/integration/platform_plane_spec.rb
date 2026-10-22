require "rails_helper"

# Plan 004 WS2.8 (platform console) and WS2.9 (unknown-subdomain seam).
RSpec.describe "integration: platform plane", type: :request do
  before { wire_integration! }

  describe "the console" do
    it "denies anonymous, allows a logged-in App Admin, and provisions through it" do
      provision_platform!(owner_email: "owner@platform.test")
      _admin, token = seed_app_admin!(email: "admin@platform.test")

      host! "example.com" # apex / bare domain

      get "/tenants"
      expect(response).to have_http_status(:forbidden)

      # App Admin authenticates AS the platform (reserved DB) via invite + token.
      oidc_login(host: "example.com", subject: "admin-sub", email: "admin@platform.test",
                 link_token: token, mode: :platform)

      get "/tenants"
      expect(response).to have_http_status(:ok)

      expect do
        post "/tenants", params: { tenant: { name: "NewCo", subdomain: "newco", owner_email: "o@newco.test" } }
      end.to change(Partitia::Tenanted::Tenant, :count).by(1)

      ApplicationRecord.with_tenant(handle_for("newco")) do
        expect(Partitia::Iam::HumanPrincipal.where(root: true).count).to eq(1)
      end
    end
  end

  describe "with_platform scope guard" do
    before { provision_platform!(owner_email: "owner@platform.test") }

    it "raises on a non-iam table and allows partitia_iam_ tables" do
      ApplicationRecord.with_tenant(Partitia::Tenanted::RESERVED_HANDLE) do
        conn = ApplicationRecord.connection
        conn.create_table(:widgets, force: true) { |t| t.string :name } unless conn.table_exists?(:widgets)
      end

      expect do
        Partitia::Tenanted.with_platform { ApplicationRecord.connection.select_all("SELECT * FROM widgets") }
      end.to raise_error(Partitia::Tenanted::PlatformScopeViolation, /widgets/)

      expect do
        Partitia::Tenanted.with_platform { Partitia::Iam::Principal.count }
      end.not_to raise_error
    end
  end

  describe "the reserved handle" do
    it "never resolves from a subdomain (stays untenanted, not the platform DB)" do
      provision_platform!(owner_email: "owner@platform.test")

      get "/probe", headers: { "HOST" => "#{Partitia::Tenanted::RESERVED_HANDLE}.example.com" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("probe: ") # untenanted — never the reserved context
    end
  end

  describe "unknown subdomain" do
    it "lands on the tenant-not-found seam" do
      get "/probe", headers: { "HOST" => "nope.example.com" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
