require "rails_helper"

# Plan 004 WS2.1, WS2.5, and the WS1.2 global-DB invariant.
RSpec.describe "integration: provisioning & isolation", type: :request do
  before { wire_integration! }

  it "seeds one Account and one root with a live token inside the tenant DB" do
    tenant = create_tenant!(subdomain: "acme", owner_email: "root@acme.test")
    token = last_bootstrap_token

    ApplicationRecord.with_tenant(tenant.handle) do
      expect(Iam::Account.count).to eq(1)
      expect(Iam::Account.instance.name).to eq("Acme")

      roots = Iam::HumanPrincipal.where(root: true)
      expect(roots.count).to eq(1)
      expect(roots.first.email).to eq("root@acme.test")
      expect(Iam::HumanPrincipal.find_by_link_token(token)).to eq(roots.first)
    end
  end

  it "isolates one tenant's identity from another's" do
    a = create_tenant!(subdomain: "aaa", owner_email: "a@x.test")
    b = create_tenant!(subdomain: "bbb", owner_email: "b@x.test")

    ApplicationRecord.with_tenant(a.handle) do
      expect(Iam::HumanPrincipal.find_by(root: true).email).to eq("a@x.test")
    end
    ApplicationRecord.with_tenant(b.handle) do
      expect(Iam::HumanPrincipal.find_by(root: true).email).to eq("b@x.test")
      expect(Iam::HumanPrincipal.count).to eq(1) # only b's own root
    end
  end

  it "rolls the Tenant back when a provisioning hook fails" do
    CnfsTenanted.after_provision << ->(_) { raise "seed boom" }
    before_count = Tenant.count

    expect { create_tenant!(subdomain: "boom") }.to raise_error(/seed boom/)
    expect(Tenant.count).to eq(before_count)
  end

  it "keeps the global DB free of identity tables (ADR 0003 §4)" do
    tables = GlobalRecord.connection.tables
      .reject { |t| t.start_with?("sqlite", "ar_internal", "schema_mig") }

    expect(tables).to eq([ "tenants" ])
    expect(tables.grep(/\Aiam_/)).to be_empty
  end
end
