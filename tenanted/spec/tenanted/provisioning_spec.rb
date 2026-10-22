require "rails_helper"

# WS4: the after_provision hook registry and Tenant provisioning contract.
RSpec.describe "tenant provisioning" do
  it "runs a registered hook inside the new tenant's DB context with the Tenant as context" do
    seen = {}
    Partitia::Tenanted.after_provision << ->(context) do
      seen[:current_tenant] = ApplicationRecord.current_tenant
      seen[:name] = context.name
      seen[:owner_email] = context.owner_email
      # Prove we can actually reach the freshly created tenant DB from inside
      # the Tenant create transaction (WS4 spike caveat).
      seen[:query] = ApplicationRecord.connection.select_value("SELECT 1")
    end

    tenant = create_tenant!(subdomain: "acme", name: "Acme", owner_email: "owner@acme.test")

    expect(seen[:current_tenant]).to eq(tenant.handle)
    expect(seen[:name]).to eq("Acme")
    expect(seen[:owner_email]).to eq("owner@acme.test")
    expect(seen[:query]).to eq(1)
  end

  it "runs hooks in registration order" do
    order = []
    Partitia::Tenanted.after_provision << ->(_) { order << :first }
    Partitia::Tenanted.after_provision << ->(_) { order << :second }

    create_tenant!(subdomain: "acme")

    expect(order).to eq(%i[first second])
  end

  it "rolls back the Tenant and drops the tenant DB when a hook raises" do
    Partitia::Tenanted.after_provision << ->(_) { raise "seeding failed" }
    tenants_before = ApplicationRecord.tenants

    expect { create_tenant!(subdomain: "boom") }.to raise_error(/seeding failed/)

    # Global row rolled back with the after_create transaction...
    expect(Partitia::Tenanted::Tenant.where(subdomain: "boom")).to be_empty
    # ...and no orphaned tenant database survives (cleanup_on_failure).
    expect(ApplicationRecord.tenants).to match_array(tenants_before)
  end

  it "provisions with no hooks registered (empty registry is valid)" do
    expect { create_tenant!(subdomain: "acme") }.not_to raise_error
    expect(ApplicationRecord.tenant_exist?(Partitia::Tenanted::Tenant.last.handle)).to be(true)
  end
end
