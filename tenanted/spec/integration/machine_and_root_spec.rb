require "rails_helper"

# Plan 004 WS2.6 (machine auth) and WS2.7 (root constraints + recovery).
RSpec.describe "integration: machines & root", type: :request do
  before { wire_integration! }

  it "authenticates a machine credential only within its own tenant" do
    a = create_tenant!(subdomain: "aaa")
    b = create_tenant!(subdomain: "bbb")

    key_id = nil
    secret = nil
    ApplicationRecord.with_tenant(a.handle) do
      machine = Partitia::Iam::MachinePrincipal.create!(name: "worker")
      credential = machine.credentials.create!
      key_id = credential.access_key_id
      secret = credential.secret

      expect(Partitia::Iam::Credential.authenticate(key_id, secret)).to eq(machine)
      # The account handle is the tenant handle, and it is embedded in the key id.
      expect(Partitia::Iam.current_account_handle).to eq(a.handle)
      expect(key_id).to include(a.handle)
    end

    ApplicationRecord.with_tenant(b.handle) do
      expect(Partitia::Iam::Credential.authenticate(key_id, secret)).to be_nil
    end
  end

  it "enforces root constraints and supports lockout recovery" do
    tenant = create_tenant!(subdomain: "acme", owner_email: "root@acme.test")

    ApplicationRecord.with_tenant(tenant.handle) do
      root = Partitia::Iam::HumanPrincipal.find_by(root: true)

      expect(Partitia::Iam::Credential.new(owner: root)).not_to be_valid          # root holds no keys
      expect(Partitia::Iam::HumanPrincipal.new(name: "root2", root: true)).not_to be_valid # second root

      root.identity_links.create!(issuer: "https://idp.example", subject: "old-sub")
      new_token = Partitia::Iam::RootRecovery.reset!

      expect(root.reload.identity_links).to be_empty                    # old links cleared
      expect(Partitia::Iam::HumanPrincipal.find_by_link_token(new_token)).to eq(root) # new token works
    end
  end

  it "creates distinct principals for the same IdP identity across tenants (JIT)" do
    create_tenant!(subdomain: "aaa")
    create_tenant!(subdomain: "bbb")

    oidc_login(host: "aaa.example.com", subject: "shared-sub", email: "s@x.test", mode: :jit)
    oidc_login(host: "bbb.example.com", subject: "shared-sub", email: "s@x.test", mode: :jit)

    ApplicationRecord.with_tenant(handle_for("aaa")) do
      expect(Partitia::Iam::IdentityLink.where(subject: "shared-sub").count).to eq(1)
    end
    ApplicationRecord.with_tenant(handle_for("bbb")) do
      expect(Partitia::Iam::IdentityLink.where(subject: "shared-sub").count).to eq(1)
      # b's non-root population is exactly the one JIT end-user (isolation held).
      expect(Partitia::Iam::HumanPrincipal.where(root: false).count).to eq(1)
    end
  end
end
