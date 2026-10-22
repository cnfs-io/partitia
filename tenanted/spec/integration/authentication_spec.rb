require "rails_helper"

# Plan 004 WS2.2–2.4: bootstrap, invite-only, and JIT login end-to-end through
# the real broker → IAM seam, in a resolved tenant's database.
RSpec.describe "integration: authentication", type: :request do
  before { wire_integration! }

  describe "root bootstrap (invite-only + token)" do
    it "links the seeded root, grants /dashboard, and consumes the token" do
      create_tenant!(subdomain: "acme", owner_email: "root@acme.test")
      token = last_bootstrap_token

      oidc_login(host: "acme.example.com", subject: "root-sub", email: "root@acme.test", link_token: token)

      get "/dashboard"
      expect(response).to have_http_status(:ok)
      expect(response.body).to start_with("dashboard: ")

      ApplicationRecord.with_tenant(handle_for("acme")) do
        root = Iam::HumanPrincipal.find_by(root: true)
        expect(root.identity_links.pluck(:issuer, :subject)).to eq([ [ OidcHelpers::ISSUER, "root-sub" ] ])
        expect(root.link_token_digest).to be_nil # consumed
      end
    end

    it "rejects a replay of the consumed bootstrap token" do
      create_tenant!(subdomain: "acme", owner_email: "root@acme.test")
      token = last_bootstrap_token
      oidc_login(host: "acme.example.com", subject: "root-sub", link_token: token)

      oidc_login(host: "acme.example.com", subject: "replayer", link_token: token)

      ApplicationRecord.with_tenant(handle_for("acme")) do
        expect(Iam::IdentityLink.where(subject: "replayer")).to be_empty
      end
    end
  end

  describe "invite-only without a token" do
    it "fails an unknown identity and grants no session" do
      create_tenant!(subdomain: "acme")

      oidc_login(host: "acme.example.com", subject: "stranger", mode: :invite_only)

      get "/dashboard"
      expect(response).to have_http_status(:unauthorized)
      ApplicationRecord.with_tenant(handle_for("acme")) do
        expect(Iam::IdentityLink.where(subject: "stranger")).to be_empty
      end
    end
  end

  describe "end-user JIT" do
    it "creates a principal + link, and reuses it on repeat login" do
      create_tenant!(subdomain: "acme")

      oidc_login(host: "acme.example.com", subject: "enduser", email: "e@acme.test", mode: :jit)

      get "/dashboard"
      expect(response).to have_http_status(:ok)

      first_id =
        ApplicationRecord.with_tenant(handle_for("acme")) do
          principal = Iam::IdentityLink.find_by(subject: "enduser").principal
          expect(principal.email).to eq("e@acme.test")
          expect(Iam::HumanPrincipal.where(root: false).count).to eq(1)
          principal.id
        end

      oidc_login(host: "acme.example.com", subject: "enduser", mode: :jit)

      ApplicationRecord.with_tenant(handle_for("acme")) do
        expect(Iam::IdentityLink.where(subject: "enduser").count).to eq(1)
        expect(Iam::IdentityLink.find_by(subject: "enduser").principal_id).to eq(first_id)
      end
    end
  end
end
