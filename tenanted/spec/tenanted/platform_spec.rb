require "rails_helper"

# WS5: the reserved platform tenant, provision_platform!, with_platform and its
# scope guard, and enumeration hygiene.
RSpec.describe "the platform plane" do
  let(:reserved) { Partitia::Tenanted::RESERVED_HANDLE }

  describe ".provision_platform!" do
    it "creates the reserved database and runs the after_provision registry" do
      context = nil
      Partitia::Tenanted.after_provision << ->(ctx) { context = { name: ctx.name, owner_email: ctx.owner_email } }

      Partitia::Tenanted.provision_platform!(owner_email: "ops@platform.test")

      expect(ApplicationRecord.tenant_exist?(reserved)).to be(true)
      expect(context).to eq(name: "Platform", owner_email: "ops@platform.test")
    end

    it "is idempotent and does not re-run the registry on a second call" do
      runs = 0
      Partitia::Tenanted.after_provision << ->(_) { runs += 1 }

      Partitia::Tenanted.provision_platform!(owner_email: "ops@platform.test")
      expect { Partitia::Tenanted.provision_platform!(owner_email: "ops@platform.test") }.not_to raise_error

      expect(runs).to eq(1)
    end

    it "creates no Tenant row for the platform" do
      Partitia::Tenanted.provision_platform!(owner_email: "ops@platform.test")
      expect(Partitia::Tenanted::Tenant.count).to eq(0)
    end
  end

  describe ".with_platform" do
    before { Partitia::Tenanted.provision_platform!(owner_email: "ops@platform.test") }

    it "runs the block inside the reserved database context" do
      seen = Partitia::Tenanted.with_platform { ApplicationRecord.current_tenant }
      expect(seen).to eq(reserved)
    end

    context "scope guard" do
      before do
        # Throwaway tables in the reserved DB to exercise both sides of the
        # allowlist. Created outside with_platform so the DDL itself isn't
        # guarded.
        ApplicationRecord.with_tenant(reserved) do
          conn = ApplicationRecord.connection
          conn.create_table(:widgets, force: true) { |t| t.string :name } unless conn.table_exists?(:widgets)
          conn.create_table(:partitia_iam_things, force: true) { |t| t.string :name } unless conn.table_exists?(:partitia_iam_things)
        end
      end

      it "raises on a non-allowlisted table" do
        expect do
          Partitia::Tenanted.with_platform { ApplicationRecord.connection.select_all("SELECT * FROM widgets") }
        end.to raise_error(Partitia::Tenanted::PlatformScopeViolation, /widgets/)
      end

      it "allows an allowlisted partitia_iam_ table" do
        expect do
          Partitia::Tenanted.with_platform { ApplicationRecord.connection.select_all("SELECT * FROM partitia_iam_things") }
        end.not_to raise_error
      end
    end
  end

  describe "Tenant rejects the reserved value" do
    it "rejects it as a handle and as a subdomain" do
      expect(Partitia::Tenanted::Tenant.new(name: "X", subdomain: "x", owner_email: "x@x.test", handle: reserved)).not_to be_valid
      expect(Partitia::Tenanted::Tenant.new(name: "X", subdomain: reserved, owner_email: "x@x.test")).not_to be_valid
    end
  end

  describe "enumeration hygiene" do
    it "excludes the reserved handle from tenant_handles and each_tenant" do
      Partitia::Tenanted.provision_platform!(owner_email: "ops@platform.test")
      create_tenant!(subdomain: "acme")

      expect(ApplicationRecord.tenants).to include(reserved)
      expect(Partitia::Tenanted.tenant_handles).not_to include(reserved)

      visited = []
      Partitia::Tenanted.each_tenant { |handle| visited << handle }
      expect(visited).not_to include(reserved)
      expect(visited).to eq(Partitia::Tenanted.tenant_handles)
    end
  end
end
